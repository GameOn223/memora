import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'codec.dart';

/// [VectorStore] on SQLite with brute-force search.
///
/// Search streams the stored vectors for one exact model, scores each with a
/// dot product and keeps the best ones in a bounded heap. Vectors are
/// normalized on the way in, and so is the query, which makes the score
/// cosine similarity. See docs/architecture.md, section 6.2.
class SqliteVectorStore implements VectorStore {
  /// Creates a store on [db].
  ///
  /// When [path] is given and a scan would read more than [isolateThreshold]
  /// vectors, the scan runs in a separate isolate on its own read-only
  /// connection so the calling isolate stays responsive. In-memory databases
  /// always scan inline.
  SqliteVectorStore(this._db, {this._path, this._isolateThreshold = 2000});

  final Database _db;
  final String? _path;
  final int _isolateThreshold;

  /// Does nothing when the memory no longer exists.
  @override
  Future<void> upsert(
    String memoryId,
    Float32List vector,
    EmbeddingModelInfo model,
    DateTime now,
  ) async {
    _checkLength(vector, model);
    _db.execute(
      '''
INSERT INTO embeddings (
  memory_id, vector, model_id, model_version, dimensions, created_at
)
SELECT ?1, ?2, ?3, ?4, ?5, ?6
WHERE EXISTS (SELECT 1 FROM memories WHERE id = ?1)
ON CONFLICT (memory_id, model_id, model_version) DO UPDATE SET
  vector = excluded.vector,
  dimensions = excluded.dimensions,
  created_at = excluded.created_at''',
      [
        memoryId,
        encodeVector(normalizeVector(vector)),
        model.storageId,
        model.version,
        model.dimensions,
        toMillis(now),
      ],
    );
  }

  @override
  Future<List<ScoredId>> search(
    Float32List query,
    EmbeddingModelInfo model, {
    Set<String>? within,
    int limit = 50,
  }) async {
    _checkLength(query, model);
    if (limit <= 0 || (within != null && within.isEmpty)) return const [];
    return _scan(
      VectorScan(
        query: normalizeVector(query),
        modelId: model.storageId,
        version: model.version,
        dimensions: model.dimensions,
        within: within?.toList(),
        limit: limit,
      ),
    );
  }

  @override
  Future<List<ScoredId>> neighbours(
    String memoryId,
    EmbeddingModelInfo model, {
    int limit = 10,
  }) async {
    if (limit <= 0) return const [];
    final rows = _db.select(
      'SELECT vector FROM embeddings '
      'WHERE memory_id = ? AND model_id = ? AND model_version = ? '
      'AND dimensions = ?',
      [memoryId, model.storageId, model.version, model.dimensions],
    );
    if (rows.isEmpty) return const [];
    return _scan(
      VectorScan(
        query: decodeVector(rows.first['vector'] as Uint8List),
        modelId: model.storageId,
        version: model.version,
        dimensions: model.dimensions,
        excludeId: memoryId,
        limit: limit,
      ),
    );
  }

  /// Newest taken first, so recent memories become searchable first during a
  /// reindex.
  @override
  Future<List<String>> missingFor(
    EmbeddingModelInfo model, {
    int limit = 100,
  }) async {
    final rows = _db.select(
      '''
SELECT m.id FROM memories m
WHERE m.status = 'ready'
  AND NOT EXISTS (
    SELECT 1 FROM embeddings e
    WHERE e.memory_id = m.id AND e.model_id = ? AND e.model_version = ?
      AND e.dimensions = ?
  )
ORDER BY m.taken_at DESC, m.seq DESC
LIMIT ?''',
      [model.storageId, model.version, model.dimensions, limit],
    );
    return [for (final row in rows) row['id'] as String];
  }

  /// Counts rows in `embeddings` alone. Foreign keys remove a memory's
  /// vectors with it, so there's nothing to join for.
  @override
  Future<int> countFor(EmbeddingModelInfo model) async {
    final row = _db.select(
      'SELECT COUNT(*) AS n FROM embeddings '
      'WHERE model_id = ? AND model_version = ? AND dimensions = ?',
      [model.storageId, model.version, model.dimensions],
    ).first;
    return row['n'] as int;
  }

  Future<List<ScoredId>> _scan(VectorScan scan) async {
    final path = _path;
    if (path != null && scan.count(_db) > _isolateThreshold) {
      return _scanInIsolate(path, scan);
    }
    return scan.run(_db);
  }

  /// Kept static so the closure sent to the isolate captures only [path] and
  /// [scan], never the connection.
  static Future<List<ScoredId>> _scanInIsolate(String path, VectorScan scan) {
    return Isolate.run(() => scan.runOnFile(path));
  }

  static void _checkLength(Float32List vector, EmbeddingModelInfo model) {
    if (vector.length != model.dimensions) {
      throw ArgumentError.value(
        vector.length,
        'vector.length',
        'Expected ${model.dimensions} dimensions for $model',
      );
    }
  }
}

/// One brute-force scan over stored vectors. Holds only plain data so it can
/// be sent to another isolate.
class VectorScan {
  VectorScan({
    required this.query,
    required this.modelId,
    required this.version,
    required this.dimensions,
    required this.limit,
    this.within,
    this.excludeId,
  });

  /// Unit-length query vector.
  final Float32List query;
  final String modelId;
  final String version;
  final int dimensions;
  final int limit;
  final List<String>? within;
  final String? excludeId;

  (String, List<Object?>) _where() {
    final clauses = [
      'e.model_id = ?',
      'e.model_version = ?',
      'e.dimensions = ?',
      "m.status != 'deleted'",
    ];
    final args = <Object?>[modelId, version, dimensions];
    if (within case final ids?) {
      clauses.add('e.memory_id IN (SELECT value FROM json_each(?))');
      args.add(jsonEncode(ids));
    }
    if (excludeId case final id?) {
      clauses.add('e.memory_id != ?');
      args.add(id);
    }
    return (clauses.join(' AND '), args);
  }

  /// The query behind [count].
  ///
  /// This one runs on the calling isolate to choose between an inline scan
  /// and an isolate, so it stays inside the `embeddings` indexes. It leaves
  /// out the join to `memories` that [run] uses to skip deleted memories, and
  /// the dimensions column, which isn't in the index. Both can only make the
  /// count slightly high, and the worst that costs is an isolate for a scan
  /// that didn't need one.
  (String, List<Object?>) countQuery() {
    final clauses = ['model_id = ?', 'model_version = ?'];
    final args = <Object?>[modelId, version];
    if (within case final ids?) {
      clauses.add('memory_id IN (SELECT value FROM json_each(?))');
      args.add(jsonEncode(ids));
    }
    if (excludeId case final id?) {
      clauses.add('memory_id != ?');
      args.add(id);
    }
    return (
      'SELECT COUNT(*) AS n FROM embeddings WHERE ${clauses.join(' AND ')}',
      args,
    );
  }

  /// Roughly how many vectors [run] would read.
  int count(Database db) {
    final (sql, args) = countQuery();
    return db.select(sql, args).first['n'] as int;
  }

  /// Scans on [db] and returns the best [limit] matches, best first. Ties keep
  /// the order the vectors were first stored in.
  List<ScoredId> run(Database db) {
    final (where, args) = _where();
    final statement = db.prepare(
      'SELECT e.memory_id, e.vector, e.id FROM embeddings e '
      'JOIN memories m ON m.id = e.memory_id WHERE $where',
    );
    try {
      final best = _TopK(limit);
      final candidate = Float32List(dimensions);
      final cursor = statement.selectCursor(args);
      while (cursor.moveNext()) {
        final row = cursor.current;
        final bytes = row.columnAt(1) as Uint8List;
        if (bytes.length != dimensions * 4) continue;
        decodeVectorInto(bytes, candidate);
        var score = 0.0;
        for (var i = 0; i < dimensions; i++) {
          score += query[i] * candidate[i];
        }
        if (score.isNaN) continue;
        best.offer(row.columnAt(0) as String, score, row.columnAt(2) as int);
      }
      return best.sorted();
    } finally {
      statement.close();
    }
  }

  /// Opens [path] read-only, scans and closes it. Used inside an isolate.
  List<ScoredId> runOnFile(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      db.execute('PRAGMA busy_timeout = 5000');
      return run(db);
    } finally {
      db.close();
    }
  }
}

typedef _Entry = ({double score, int order, String id});

/// Keeps the [capacity] best entries seen so far in a binary min-heap whose
/// root is the worst kept entry.
class _TopK {
  _TopK(this.capacity);

  final int capacity;
  final List<_Entry> _heap = [];

  /// Lower score is worse. On equal scores the later order is worse.
  static bool _worse(_Entry a, _Entry b) =>
      a.score < b.score || (a.score == b.score && a.order > b.order);

  void offer(String id, double score, int order) {
    final entry = (score: score, order: order, id: id);
    if (_heap.length < capacity) {
      _heap.add(entry);
      _siftUp(_heap.length - 1);
    } else if (_worse(_heap.first, entry)) {
      _heap[0] = entry;
      _siftDown(0);
    }
  }

  List<ScoredId> sorted() {
    final entries = [..._heap]
      ..sort((a, b) {
        if (_worse(a, b)) return 1;
        if (_worse(b, a)) return -1;
        return 0;
      });
    return [for (final e in entries) ScoredId(e.id, e.score)];
  }

  void _siftUp(int index) {
    var child = index;
    while (child > 0) {
      final parent = (child - 1) >> 1;
      if (!_worse(_heap[child], _heap[parent])) return;
      _swap(child, parent);
      child = parent;
    }
  }

  void _siftDown(int index) {
    var parent = index;
    while (true) {
      final left = parent * 2 + 1;
      final right = left + 1;
      var worst = parent;
      if (left < _heap.length && _worse(_heap[left], _heap[worst])) {
        worst = left;
      }
      if (right < _heap.length && _worse(_heap[right], _heap[worst])) {
        worst = right;
      }
      if (worst == parent) return;
      _swap(parent, worst);
      parent = worst;
    }
  }

  void _swap(int a, int b) {
    final tmp = _heap[a];
    _heap[a] = _heap[b];
    _heap[b] = tmp;
  }
}
