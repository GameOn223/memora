import 'dart:convert';

import 'package:memora_core/memora_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'codec.dart';
import 'fts_query.dart';
import 'rows.dart';

/// Attribute types shown as a memory's identifier fact on cards.
const _identifierTypes = [
  'booking_reference',
  'pnr',
  'order_number',
  'invoice_number',
  'tracking_number',
];

/// Column weights for bm25, in `memories_fts` column order: summary,
/// extracted_text, visual_description, keywords, entities. A hit in the short
/// fields the model wrote says more than a hit somewhere in long OCR text.
const _bm25 = 'bm25(memories_fts, 3.0, 1.0, 1.5, 2.0, 2.0)';

/// [SearchStore] on SQLite.
///
/// Deleted memories never appear in results. All user input is bound as
/// parameters, and full-text input goes through [ftsMatchExpression].
class SqliteSearchStore implements SearchStore {
  SqliteSearchStore(this._db);

  final Database _db;

  @override
  Future<List<String>> structured(
    RetrievalQuery query, {
    int limit = 500,
  }) async {
    final where = <String>["m.status != 'deleted'"];
    final args = <Object?>[];

    if (query.categories.isNotEmpty) {
      where.add('m.category IN (SELECT value FROM json_each(?))');
      args.add(jsonEncode(query.categories.toList()));
    }
    if (query.statuses.isNotEmpty) {
      where.add('m.status IN (SELECT value FROM json_each(?))');
      args.add(jsonEncode([for (final s in query.statuses) s.dbValue]));
    }
    if (query.takenBetween?.start case final start?) {
      where.add('m.taken_at >= ?');
      args.add(toMillis(start));
    }
    if (query.takenBetween?.end case final end?) {
      where.add('m.taken_at < ?');
      args.add(toMillis(end));
    }
    if (query.within case final within?) {
      where.add('m.id IN (SELECT value FROM json_each(?))');
      args.add(jsonEncode(within.toList()));
    }

    for (final filter in query.entities) {
      final clause = StringBuffer(
        'EXISTS (SELECT 1 FROM entities e WHERE e.memory_id = m.id '
        r"AND e.normalized_value LIKE ? ESCAPE '\'",
      );
      args.add('%${_escapeLike(_normalize(filter.value))}%');
      if (filter.type case final type?) {
        clause.write(' AND e.type = ?');
        args.add(type);
      }
      clause.write(')');
      where.add(clause.toString());
    }

    for (final filter in query.attributes) {
      final clause = StringBuffer(
        'EXISTS (SELECT 1 FROM attributes a WHERE a.memory_id = m.id '
        'AND a.type = ?',
      );
      args.add(filter.type);
      if (filter.min case final min?) {
        clause.write(' AND a.value_num >= ?');
        args.add(min);
      }
      if (filter.max case final max?) {
        clause.write(' AND a.value_num <= ?');
        args.add(max);
      }
      if (filter.currency case final currency?) {
        clause.write(' AND a.currency = ? COLLATE NOCASE');
        args.add(currency.trim());
      }
      if (filter.dateRange?.start case final start?) {
        clause.write(' AND a.value_date >= ?');
        args.add(isoDateOnOrAfter(start));
      }
      if (filter.dateRange?.end case final end?) {
        clause.write(' AND a.value_date < ?');
        args.add(isoDateOnOrAfter(end));
      }
      if (filter.equals case final equals?) {
        clause.write(' AND a.value = ? COLLATE NOCASE');
        args.add(equals.trim());
      }
      clause.write(')');
      where.add(clause.toString());
    }

    args.add(limit);
    final rows = _db.select(
      'SELECT m.id FROM memories m WHERE ${where.join(' AND ')} '
      'ORDER BY m.taken_at DESC, m.seq DESC LIMIT ?',
      args,
    );
    return [for (final row in rows) row['id'] as String];
  }

  @override
  Future<List<ScoredId>> fullText(
    String text, {
    Set<String>? within,
    int limit = 50,
  }) async {
    final match = ftsMatchExpression(text);
    if (match == null || (within != null && within.isEmpty)) return const [];

    final args = <Object?>[match];
    var restrict = '';
    if (within != null) {
      restrict = 'AND m.id IN (SELECT value FROM json_each(?))';
      args.add(jsonEncode(within.toList()));
    }
    args.add(limit);

    final rows = _db.select('''
SELECT m.id AS id, $_bm25 AS rank
FROM memories_fts
JOIN memories m ON m.seq = memories_fts.rowid
WHERE memories_fts MATCH ? AND m.status != 'deleted' $restrict
ORDER BY rank ASC, m.taken_at DESC, m.seq DESC
LIMIT ?''', args);
    return [
      for (final row in rows)
        ScoredId(row['id'] as String, -(row['rank'] as num).toDouble()),
    ];
  }

  @override
  Future<List<MemoryCard>> cards(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final idsJson = jsonEncode(ids);

    final facts = <String, _CardFacts>{};
    for (final row in _db.select(
      'SELECT * FROM attributes '
      'WHERE memory_id IN (SELECT value FROM json_each(?)) '
      'ORDER BY id',
      [idsJson],
    )) {
      facts
          .putIfAbsent(row['memory_id'] as String, _CardFacts.new)
          .offer(attributeFromRow(row));
    }

    final byId = <String, MemoryCard>{};
    for (final row in _db.select(
      'SELECT id, taken_at, status, summary, category, thumbnail_path '
      'FROM memories '
      "WHERE id IN (SELECT value FROM json_each(?)) AND status != 'deleted'",
      [idsJson],
    )) {
      final id = row['id'] as String;
      byId[id] = MemoryCard(
        id: id,
        takenAt: fromMillis(row['taken_at'] as int),
        status: ProcessingStatus.fromDb(row['status'] as String),
        summary: row['summary'] as String?,
        category: row['category'] as String?,
        thumbnailPath: row['thumbnail_path'] as String?,
        facts: facts[id]?.toMap() ?? const {},
      );
    }
    return [for (final id in ids) ?byId[id]];
  }

  @override
  Future<List<AttributeValue>> attributeValues(
    List<String> ids,
    String type,
  ) async {
    if (ids.isEmpty) return const [];
    final order = <String, int>{};
    for (final (index, id) in ids.indexed) {
      order.putIfAbsent(id, () => index);
    }

    final rows = _db.select(
      '''
SELECT a.*, m.taken_at AS memory_taken_at
FROM attributes a
JOIN memories m ON m.id = a.memory_id
WHERE a.memory_id IN (SELECT value FROM json_each(?))
  AND a.type = ?
  AND m.status != 'deleted'
ORDER BY a.id''',
      [jsonEncode(ids), type],
    );
    final values = [
      for (final row in rows)
        AttributeValue(
          memoryId: row['memory_id'] as String,
          attribute: attributeFromRow(row),
          takenAt: fromMillis(row['memory_taken_at'] as int),
        ),
    ];
    // List.sort is stable, so attributes of one memory keep their order.
    values.sort((a, b) => order[a.memoryId]!.compareTo(order[b.memoryId]!));
    return values;
  }

  @override
  Future<List<ScoredId>> sharingEntities(
    String memoryId, {
    int limit = 20,
  }) async {
    final rows = _db.select(
      '''
SELECT other.memory_id AS id, COUNT(DISTINCT other.normalized_value) AS shared
FROM entities mine
JOIN entities other
  ON other.normalized_value = mine.normalized_value
 AND other.memory_id != mine.memory_id
JOIN memories m ON m.id = other.memory_id
WHERE mine.memory_id = ?
  AND mine.normalized_value != ''
  AND m.status != 'deleted'
GROUP BY other.memory_id
ORDER BY shared DESC, MAX(m.taken_at) DESC, other.memory_id
LIMIT ?''',
      [memoryId, limit],
    );
    return [
      for (final row in rows)
        ScoredId(row['id'] as String, (row['shared'] as int).toDouble()),
    ];
  }

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}

/// The key facts for one card, collected from attributes in stored order.
class _CardFacts {
  StoredAttribute? amount;
  StoredAttribute? date;
  StoredAttribute? identifier;

  void offer(StoredAttribute attribute) {
    if (attribute.type == 'amount') {
      amount ??= attribute;
    } else if (attribute.valueDate != null) {
      date ??= attribute;
    } else if (_identifierTypes.contains(attribute.type)) {
      identifier ??= attribute;
    }
  }

  /// Amount first, then the date, then the identifier.
  Map<String, String> toMap() => {
    if (amount case final a?) 'amount': a.value,
    if (date case final d?) d.type: d.value,
    if (identifier case final i?) i.type: i.value,
  };
}
