import 'dart:convert';

import 'package:memora_core/memora_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'codec.dart';
import 'rows.dart';
import 'transactions.dart';

/// [MemoryStore] on SQLite.
///
/// Writes that touch AI output rewrite the memory's `memories_fts` row in the
/// same transaction, so the index never drifts from the data.
class SqliteMemoryStore implements MemoryStore {
  SqliteMemoryStore(this._db);

  final Database _db;

  int _seenDataVersion = -1;
  int _seenTotalChanges = -1;
  int _version = 0;

  @override
  Future<InsertOutcome> insertCaptured(
    List<NewMemory> memories,
    DateTime now,
  ) async {
    final inserted = <String>[];
    final duplicates = <NewMemory>[];
    _db.transaction(() {
      final statement = _db.prepare('''
INSERT INTO memories (
  id, image_path, source, sha256, mime_type, width, height, byte_size,
  taken_at, added_at, updated_at, status
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'captured')
ON CONFLICT (sha256) DO NOTHING
RETURNING id''');
      try {
        final millis = toMillis(now);
        for (final memory in memories) {
          final rows = statement.select([
            memory.id,
            memory.imagePath,
            memory.source.dbValue,
            memory.sha256,
            memory.mimeType,
            memory.width,
            memory.height,
            memory.byteSize,
            toMillis(memory.takenAt),
            millis,
            millis,
          ]);
          if (rows.isEmpty) {
            duplicates.add(memory);
          } else {
            inserted.add(memory.id);
          }
        }
      } finally {
        statement.close();
      }
    }, immediate: true);
    return InsertOutcome(insertedIds: inserted, duplicates: duplicates);
  }

  @override
  Future<Memory?> getMemory(String id) async {
    final rows = _db.select('SELECT * FROM memories WHERE id = ?', [id]);
    return rows.isEmpty ? null : memoryFromRow(rows.first);
  }

  @override
  Future<List<Memory>> getMemories(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = _db.select(
      'SELECT * FROM memories WHERE id IN (SELECT value FROM json_each(?))',
      [jsonEncode(ids)],
    );
    final byId = {
      for (final row in rows) row['id'] as String: memoryFromRow(row),
    };
    return [for (final id in ids) ?byId[id]];
  }

  @override
  Future<MemoryDetails?> getDetails(String id) async {
    final memory = await getMemory(id);
    if (memory == null) return null;

    final entities = [
      for (final row in _db.select(
        'SELECT type, value, normalized_value FROM entities '
        'WHERE memory_id = ? ORDER BY id',
        [id],
      ))
        StoredEntity(
          type: row['type'] as String,
          value: row['value'] as String,
          normalizedValue: row['normalized_value'] as String,
        ),
    ];
    final attributes = [
      for (final row in _db.select(
        'SELECT * FROM attributes WHERE memory_id = ? ORDER BY id',
        [id],
      ))
        attributeFromRow(row),
    ];
    final keywords = [
      for (final row in _db.select(
        'SELECT keyword FROM keywords WHERE memory_id = ? ORDER BY rowid',
        [id],
      ))
        row['keyword'] as String,
    ];
    final processing = [
      for (final row in _db.select(
        'SELECT * FROM processing_metadata WHERE memory_id = ? '
        'ORDER BY created_at DESC, id DESC',
        [id],
      ))
        ProcessingRecord(
          memoryId: id,
          capability: Capability.fromKey(row['capability'] as String),
          provider: row['provider'] as String,
          model: row['model'] as String,
          version: row['version'] as String?,
          outcome: ProcessingOutcome.fromDb(row['status'] as String),
          latency: switch (row['latency_ms']) {
            final int ms => Duration(milliseconds: ms),
            _ => null,
          },
          error: row['error'] as String?,
          createdAt: fromMillis(row['created_at'] as int),
        ),
    ];
    final conversationCount =
        _db.select(
              'SELECT COUNT(DISTINCT m.conversation_id) AS n '
              'FROM message_references r '
              'JOIN messages m ON m.id = r.message_id '
              'WHERE r.memory_id = ?',
              [id],
            ).first['n']
            as int;

    return MemoryDetails(
      memory: memory,
      entities: entities,
      attributes: attributes,
      keywords: keywords,
      processing: processing,
      conversationCount: conversationCount,
    );
  }

  @override
  Future<List<Memory>> listMemories(MemoryListQuery query) async {
    final where = <String>["status != 'deleted'"];
    final args = <Object?>[];
    if (query.categories.isNotEmpty) {
      where.add('category IN (SELECT value FROM json_each(?))');
      args.add(jsonEncode(query.categories.toList()));
    }
    if (query.statuses.isNotEmpty) {
      where.add('status IN (SELECT value FROM json_each(?))');
      args.add(jsonEncode([for (final s in query.statuses) s.dbValue]));
    }
    if (query.takenBetween?.start case final start?) {
      where.add('taken_at >= ?');
      args.add(toMillis(start));
    }
    if (query.takenBetween?.end case final end?) {
      where.add('taken_at < ?');
      args.add(toMillis(end));
    }
    final order = switch (query.sort) {
      MemorySort.newest => 'taken_at DESC, seq DESC',
      MemorySort.oldest => 'taken_at ASC, seq ASC',
      MemorySort.category =>
        'category IS NULL, category ASC, taken_at DESC, seq DESC',
      MemorySort.recentlyViewed =>
        'last_viewed_at IS NULL, last_viewed_at DESC, taken_at DESC, seq DESC',
    };
    args
      ..add(query.limit)
      ..add(query.offset);
    final rows = _db.select(
      'SELECT * FROM memories WHERE ${where.join(' AND ')} '
      'ORDER BY $order LIMIT ? OFFSET ?',
      args,
    );
    return [for (final row in rows) memoryFromRow(row)];
  }

  @override
  Future<List<FacetCount>> categoryCounts() async {
    final rows = _db.select('''
SELECT category, COUNT(*) AS n FROM memories
WHERE category IS NOT NULL AND status != 'deleted'
GROUP BY category
ORDER BY n DESC, category ASC''');
    return [
      for (final row in rows)
        FacetCount(row['category'] as String, row['n'] as int),
    ];
  }

  @override
  Future<QueueSummary> queueSummary() async {
    final row = _db.select('''
SELECT
  COUNT(*) AS total,
  COALESCE(SUM(status = 'ready'), 0) AS ready,
  COALESCE(SUM(status IN $waitingStatuses), 0) AS waiting,
  COALESCE(SUM(status = 'processing'), 0) AS processing,
  COALESCE(SUM(status = 'failed'), 0) AS failed
FROM memories
WHERE status != 'deleted' ''').first;
    return QueueSummary(
      total: row['total'] as int,
      ready: row['ready'] as int,
      waiting: row['waiting'] as int,
      processing: row['processing'] as int,
      failed: row['failed'] as int,
    );
  }

  @override
  Future<StorageStats> storageStats() async {
    final row = _db.select('''
SELECT COUNT(*) AS n, COALESCE(SUM(byte_size), 0) AS bytes
FROM memories WHERE status != 'deleted' ''').first;
    return StorageStats(
      memoryCount: row['n'] as int,
      imageBytes: row['bytes'] as int,
    );
  }

  /// Does nothing when the memory no longer exists, for example when it was
  /// deleted while a worker was processing it.
  @override
  Future<void> saveUnderstanding(
    String id,
    MemoryUnderstanding understanding,
    NormalizedFacts facts,
    DateTime now,
  ) async {
    _db.transaction(() {
      final updated = _db.select(
        '''
UPDATE memories
SET summary = ?, visual_description = ?, extracted_text = ?, category = ?,
    updated_at = ?
WHERE id = ?
RETURNING seq''',
        [
          blankToNull(understanding.summary),
          blankToNull(understanding.visualDescription),
          blankToNull(understanding.extractedText),
          blankToNull(understanding.category),
          toMillis(now),
          id,
        ],
      );
      if (updated.isEmpty) return;
      final seq = updated.first['seq'] as int;

      _db
        ..execute('DELETE FROM entities WHERE memory_id = ?', [id])
        ..execute('DELETE FROM attributes WHERE memory_id = ?', [id])
        ..execute('DELETE FROM keywords WHERE memory_id = ?', [id]);

      _insertEach(
        'INSERT INTO entities (memory_id, type, value, normalized_value) '
        'VALUES (?, ?, ?, ?)',
        [
          for (final e in facts.entities)
            [id, e.type, e.value, e.normalizedValue],
        ],
      );
      _insertEach(
        'INSERT INTO attributes '
        '(memory_id, type, value, value_num, value_date, currency, label) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          for (final a in facts.attributes)
            [id, a.type, a.value, a.valueNum, a.valueDate, a.currency, a.label],
        ],
      );
      _insertEach(
        'INSERT OR IGNORE INTO keywords (memory_id, keyword) VALUES (?, ?)',
        [
          for (final k in facts.keywords) [id, k],
        ],
      );

      _db
        ..execute('DELETE FROM memories_fts WHERE rowid = ?', [seq])
        ..execute(
          'INSERT INTO memories_fts (rowid, summary, extracted_text, '
          'visual_description, keywords, entities) VALUES (?, ?, ?, ?, ?, ?)',
          [
            seq,
            understanding.summary,
            understanding.extractedText,
            understanding.visualDescription,
            facts.keywords.join(' '),
            [for (final e in facts.entities) e.value].join(' '),
          ],
        );
    }, immediate: true);
  }

  @override
  Future<void> setThumbnail(
    String id,
    String thumbnailPath,
    DateTime now,
  ) async {
    _db.execute(
      'UPDATE memories SET thumbnail_path = ?, updated_at = ? WHERE id = ?',
      [thumbnailPath, toMillis(now), id],
    );
  }

  @override
  Future<void> markViewed(String id, DateTime now) async {
    _db.execute('UPDATE memories SET last_viewed_at = ? WHERE id = ?', [
      toMillis(now),
      id,
    ]);
  }

  /// Does nothing when the memory no longer exists.
  @override
  Future<void> addProcessingRecord(ProcessingRecord record) async {
    _db.execute(
      '''
INSERT INTO processing_metadata (
  memory_id, capability, provider, model, version, status, latency_ms, error,
  created_at
)
SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?
WHERE EXISTS (SELECT 1 FROM memories WHERE id = ?)''',
      [
        record.memoryId,
        record.capability.key,
        record.provider,
        record.model,
        record.version,
        record.outcome.dbValue,
        record.latency?.inMilliseconds,
        record.error,
        toMillis(record.createdAt),
        record.memoryId,
      ],
    );
  }

  @override
  Future<MemoryFiles?> deleteMemory(String id) async {
    return _db.transaction(() {
      final rows = _db.select(
        'SELECT seq, image_path, thumbnail_path FROM memories WHERE id = ?',
        [id],
      );
      if (rows.isEmpty) return null;
      final row = rows.first;
      _db
        ..execute('DELETE FROM memories_fts WHERE rowid = ?', [row['seq']])
        ..execute('DELETE FROM memories WHERE id = ?', [id]);
      return MemoryFiles(
        imagePath: row['image_path'] as String,
        thumbnailPath: row['thumbnail_path'] as String?,
      );
    }, immediate: true);
  }

  @override
  Future<List<MemoryFiles>> deleteAll() async {
    return _db.transaction(() {
      final rows = _db.select(
        'SELECT image_path, thumbnail_path FROM memories ORDER BY seq',
      );
      _db
        ..execute('DELETE FROM memories_fts')
        ..execute('DELETE FROM memories');
      return [
        for (final row in rows)
          MemoryFiles(
            imagePath: row['image_path'] as String,
            thumbnailPath: row['thumbnail_path'] as String?,
          ),
      ];
    }, immediate: true);
  }

  @override
  Future<List<Memory>> missingThumbnails({int limit = 50}) async {
    final rows = _db.select(
      'SELECT * FROM memories '
      "WHERE thumbnail_path IS NULL AND status != 'deleted' "
      'ORDER BY added_at ASC, seq ASC LIMIT ?',
      [limit],
    );
    return [for (final row in rows) memoryFromRow(row)];
  }

  /// Combines `PRAGMA data_version`, which moves when another connection
  /// commits, with `total_changes()`, which moves when this connection
  /// writes. The returned counter goes up whenever either one has changed
  /// since the previous call.
  @override
  Future<int> dataVersion() async {
    final row = _db.select('''
SELECT
  (SELECT data_version FROM pragma_data_version) AS data_version,
  total_changes() AS changes''').first;
    final dataVersion = row['data_version'] as int;
    final changes = row['changes'] as int;
    if (dataVersion != _seenDataVersion || changes != _seenTotalChanges) {
      _seenDataVersion = dataVersion;
      _seenTotalChanges = changes;
      _version++;
    }
    return _version;
  }

  void _insertEach(String sql, List<List<Object?>> rows) {
    if (rows.isEmpty) return;
    final statement = _db.prepare(sql);
    try {
      for (final args in rows) {
        statement.execute(args);
      }
    } finally {
      statement.close();
    }
  }
}
