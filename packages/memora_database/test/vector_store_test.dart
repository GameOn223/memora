import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';
import 'package:memora_database/memora_database.dart';
import 'package:memora_database/src/codec.dart';
import 'package:memora_database/src/sqlite_vector_store.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

const bge = EmbeddingModelInfo(
  provider: 'local',
  modelId: 'bge-small-en-v1.5',
  version: '1',
  dimensions: 4,
);

Float32List vec(List<double> values) => Float32List.fromList(values);

void main() {
  late MemoraDatabase db;
  late VectorStore vectors;
  final now = DateTime.utc(2026, 9, 15);

  setUp(() {
    db = openTestDatabase();
    vectors = db.vectors;
  });

  Future<String> ready() async {
    final id = await seedMemory(db);
    setStatus(db, id, ProcessingStatus.ready);
    return id;
  }

  group('upsert', () {
    test('keeps one row per memory and model with the latest vector', () async {
      final id = await ready();
      await vectors.upsert(id, vec([1, 0, 0, 0]), bge, now);
      final later = now.add(const Duration(hours: 1));
      await vectors.upsert(id, vec([0, 1, 0, 0]), bge, later);

      final rows = db.connection.select('SELECT * FROM embeddings');
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(decodeVector(row['vector'] as Uint8List), [0, 1, 0, 0]);
      expect(row['model_id'], 'local/bge-small-en-v1.5');
      expect(row['model_version'], '1');
      expect(row['dimensions'], 4);
      expect(row['created_at'], later.millisecondsSinceEpoch);
    });

    test('keeps separate rows for separate model versions', () async {
      final id = await ready();
      await vectors.upsert(id, vec([1, 0, 0, 0]), bge, now);
      await vectors.upsert(id, vec([0, 1, 0, 0]), _version('2'), now);
      expect(scalar(db, 'SELECT COUNT(*) FROM embeddings'), 2);
    });

    test('stores vectors L2-normalized', () async {
      final id = await ready();
      await vectors.upsert(id, vec([3, 0, 4, 0]), bge, now);
      final stored = decodeVector(
        scalar(db, 'SELECT vector FROM embeddings')! as Uint8List,
      );
      expect(stored[0], closeTo(0.6, 1e-6));
      expect(stored[2], closeTo(0.8, 1e-6));
    });

    test('rejects a vector whose length does not match the model', () async {
      final id = await ready();
      expect(
        () => vectors.upsert(id, vec([1, 0, 0]), bge, now),
        throwsArgumentError,
      );
    });

    test('does nothing for a memory that no longer exists', () async {
      await vectors.upsert('gone', vec([1, 0, 0, 0]), bge, now);
      expect(scalar(db, 'SELECT COUNT(*) FROM embeddings'), 0);
    });
  });

  group('search', () {
    late String east;
    late String northEast;
    late String north;
    late String west;
    late String otherVersion;
    late String otherDimensions;

    setUp(() async {
      east = await ready();
      northEast = await ready();
      north = await ready();
      west = await ready();
      otherVersion = await ready();
      otherDimensions = await ready();
      await vectors.upsert(north, vec([0, 1, 0, 0]), bge, now);
      await vectors.upsert(east, vec([1, 0, 0, 0]), bge, now);
      await vectors.upsert(west, vec([-1, 0, 0, 0]), bge, now);
      await vectors.upsert(northEast, vec([0.8, 0.6, 0, 0]), bge, now);
      await vectors.upsert(otherVersion, vec([1, 0, 0, 0]), _version('2'), now);
      await vectors.upsert(
        otherDimensions,
        vec([1, 0, 0]),
        _dimensions(3),
        now,
      );
    });

    test('ranks by dot product among vectors of the exact model', () async {
      final hits = await vectors.search(vec([1, 0, 0, 0]), bge);
      expect(hits.map((h) => h.id), [east, northEast, north, west]);
      expect(hits[0].score, closeTo(1, 1e-6));
      expect(hits[1].score, closeTo(0.8, 1e-6));
      expect(hits[2].score, closeTo(0, 1e-6));
      expect(hits[3].score, closeTo(-1, 1e-6));
    });

    test('normalizes the query so scores are cosine similarity', () async {
      final hits = await vectors.search(vec([10, 0, 0, 0]), bge, limit: 1);
      expect(hits.single.score, closeTo(1, 1e-6));
    });

    test('respects within and limit', () async {
      final limited = await vectors.search(vec([1, 0, 0, 0]), bge, limit: 2);
      expect(limited.map((h) => h.id), [east, northEast]);

      final within = await vectors.search(
        vec([1, 0, 0, 0]),
        bge,
        within: {north, west, otherVersion},
      );
      expect(within.map((h) => h.id), [north, west]);

      expect(await vectors.search(vec([1, 0, 0, 0]), bge, within: {}), isEmpty);
      expect(await vectors.search(vec([1, 0, 0, 0]), bge, limit: 0), isEmpty);
    });

    test('keeps ties in insertion order', () async {
      final twin = await ready();
      await vectors.upsert(twin, vec([1, 0, 0, 0]), bge, now);
      final hits = await vectors.search(vec([1, 0, 0, 0]), bge, limit: 2);
      expect(hits.map((h) => h.id), [east, twin]);
    });

    test('skips deleted memories', () async {
      setStatus(db, east, ProcessingStatus.deleted);
      final hits = await vectors.search(vec([1, 0, 0, 0]), bge, limit: 1);
      expect(hits.single.id, northEast);
    });

    test('finds nothing for a model with no vectors', () async {
      final hits = await vectors.search(
        vec([1, 0, 0, 0]),
        const EmbeddingModelInfo(
          provider: 'openai',
          modelId: 'bge-small-en-v1.5',
          version: '1',
          dimensions: 4,
        ),
      );
      expect(hits, isEmpty);
    });

    test('rejects a query whose length does not match the model', () async {
      expect(() => vectors.search(vec([1, 0]), bge), throwsArgumentError);
    });

    test('neighbours exclude the memory itself', () async {
      final hits = await vectors.neighbours(east, bge, limit: 2);
      expect(hits.map((h) => h.id), [northEast, north]);
      expect(hits.first.score, closeTo(0.8, 1e-6));

      expect(await vectors.neighbours(otherVersion, bge), isEmpty);
      expect(await vectors.neighbours('missing', bge), isEmpty);
    });
  });

  group('the pre-scan count', () {
    VectorScan scanFor({Set<String>? within, String? excludeId}) => VectorScan(
      query: vec([1, 0, 0, 0]),
      modelId: bge.storageId,
      version: bge.version,
      dimensions: bge.dimensions,
      limit: 10,
      within: within?.toList(),
      excludeId: excludeId,
    );

    String planFor(VectorScan scan) {
      final (sql, args) = scan.countQuery();
      return db.connection
          .select('EXPLAIN QUERY PLAN $sql', args)
          .map((row) => row['detail'] as String)
          .join(' | ');
    }

    test('reads the embeddings index without touching memories', () {
      expect(planFor(scanFor()), contains('COVERING INDEX embeddings_model'));
      for (final scan in [
        scanFor(),
        scanFor(within: {'a', 'b'}),
        scanFor(excludeId: 'a'),
      ]) {
        expect(planFor(scan), isNot(contains('memories')));
      }
    });

    test('still counts the rows a scan would read', () async {
      final kept = await ready();
      final other = await ready();
      await vectors.upsert(kept, vec([1, 0, 0, 0]), bge, now);
      await vectors.upsert(other, vec([0, 1, 0, 0]), bge, now);
      await vectors.upsert(other, vec([0, 1, 0, 0]), _version('2'), now);

      expect(scanFor().count(db.connection), 2);
      expect(scanFor(within: {kept}).count(db.connection), 1);
      expect(scanFor(excludeId: kept).count(db.connection), 1);
    });
  });

  group('bookkeeping', () {
    test('missingFor lists ready memories without a vector', () async {
      final embedded = await ready();
      final stale = await ready();
      final bare = await ready();
      final waiting = await seedMemory(db);
      await vectors.upsert(embedded, vec([1, 0, 0, 0]), bge, now);
      await vectors.upsert(stale, vec([1, 0, 0, 0]), _version('0'), now);

      expect((await vectors.missingFor(bge)).toSet(), {stale, bare});
      expect(await vectors.missingFor(bge, limit: 1), hasLength(1));
      expect(await vectors.missingFor(bge), isNot(contains(waiting)));
      expect((await vectors.missingFor(_version('0'))).toSet(), {
        embedded,
        bare,
      });
    });

    test('countFor counts vectors of the exact model', () async {
      expect(await vectors.countFor(bge), 0);
      for (final id in [await ready(), await ready()]) {
        await vectors.upsert(id, vec([1, 0, 0, 0]), bge, now);
        await vectors.upsert(id, vec([1, 0, 0, 0]), _version('2'), now);
      }
      expect(await vectors.countFor(bge), 2);
      expect(await vectors.countFor(_version('2')), 2);
      expect(await vectors.countFor(_dimensions(8)), 0);
    });
  });

  group('large collections', () {
    const model = EmbeddingModelInfo(
      provider: 'local',
      modelId: 'bge-small-en-v1.5',
      version: '1',
      dimensions: 384,
    );

    Future<Map<String, Float32List>> seedRandom(
      MemoraDatabase target,
      int count,
    ) async {
      final random = Random(42);
      final stored = <String, Float32List>{};
      final connection = target.connection..execute('BEGIN');
      final insert = connection.prepare(
        'INSERT INTO memories (id, image_path, source, sha256, mime_type, '
        'width, height, byte_size, taken_at, added_at, updated_at, status) '
        "VALUES (?, 'x.png', 'gallery', ?, 'image/png', 1, 1, 1, ?, 0, 0, "
        "'ready')",
      );
      for (var i = 0; i < count; i++) {
        final id = 'bulk-$i';
        insert.execute([id, 'sha-$i', i]);
        final vector = Float32List(model.dimensions);
        for (var d = 0; d < vector.length; d++) {
          vector[d] = random.nextDouble() * 2 - 1;
        }
        await target.vectors.upsert(id, vector, model, now);
        stored[id] = vector;
      }
      insert.close();
      connection.execute('COMMIT');
      return stored;
    }

    List<String> bruteForceTop(
      Map<String, Float32List> stored,
      Float32List query,
      int k,
    ) {
      double norm(Float32List v) =>
          sqrt(v.fold<double>(0, (sum, x) => sum + x * x));
      final scores = {
        for (final MapEntry(:key, :value) in stored.entries)
          key: () {
            var dot = 0.0;
            for (var i = 0; i < value.length; i++) {
              dot += value[i] * query[i];
            }
            return dot / norm(value);
          }(),
      };
      final ids = scores.keys.toList()
        ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
      return ids.take(k).toList();
    }

    test('searches 5,000 vectors of 384 dimensions quickly', () async {
      final stored = await seedRandom(db, 5000);
      final query = stored['bulk-1234']!;

      final stopwatch = Stopwatch()..start();
      final hits = await vectors.search(query, model, limit: 20);
      stopwatch.stop();

      expect(hits.first.id, 'bulk-1234');
      expect(hits.map((h) => h.id), bruteForceTop(stored, query, 20));

      const budget = Duration(milliseconds: 1500);
      if (stopwatch.elapsed > budget &&
          Platform.environment.containsKey('CI')) {
        markTestSkipped(
          'Vector search took ${stopwatch.elapsedMilliseconds} ms on this CI '
          'runner. The timing guard only fails on local machines.',
        );
        return;
      }
      expect(stopwatch.elapsed, lessThan(budget));
    });

    test('file databases scan large collections in an isolate', () async {
      final path = tempDatabasePath();
      final fileDb = MemoraDatabase.open(path);
      addTearDown(fileDb.close);
      final stored = await seedRandom(fileDb, 2100);
      final query = stored['bulk-7']!;

      final hits = await fileDb.vectors.search(query, model, limit: 5);
      expect(hits.map((h) => h.id), bruteForceTop(stored, query, 5));

      final within = await fileDb.vectors.search(
        query,
        model,
        within: {'bulk-1', 'bulk-2'},
      );
      expect(within.map((h) => h.id).toSet(), {'bulk-1', 'bulk-2'});

      final neighbours = await fileDb.vectors.neighbours(
        'bulk-7',
        model,
        limit: 4,
      );
      expect(
        neighbours.map((h) => h.id),
        bruteForceTop(stored, query, 5).skip(1),
      );
    });

    test('isolate scans match inline scans', () async {
      final path = tempDatabasePath();
      final fileDb = MemoraDatabase.open(path);
      addTearDown(fileDb.close);
      final stored = await seedRandom(fileDb, 50);
      final query = stored['bulk-3']!;

      final inline = SqliteVectorStore(fileDb.connection);
      final isolated = SqliteVectorStore(
        fileDb.connection,
        path: path,
        isolateThreshold: 0,
      );
      final expected = await inline.search(query, model, limit: 10);
      final actual = await isolated.search(query, model, limit: 10);
      expect(actual, expected);
    });
  });
}

EmbeddingModelInfo _version(String version) => EmbeddingModelInfo(
  provider: bge.provider,
  modelId: bge.modelId,
  version: version,
  dimensions: bge.dimensions,
);

EmbeddingModelInfo _dimensions(int dimensions) => EmbeddingModelInfo(
  provider: bge.provider,
  modelId: bge.modelId,
  version: bge.version,
  dimensions: dimensions,
);
