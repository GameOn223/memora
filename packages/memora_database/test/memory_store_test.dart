import 'package:memora_core/memora_core.dart';
import 'package:memora_database/memora_database.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  late MemoraDatabase db;
  late MemoryStore store;
  final now = DateTime.utc(2026, 9, 15, 10);

  setUp(() {
    db = openTestDatabase();
    store = db.memories;
  });

  group('insertCaptured', () {
    test('inserts captured rows and returns ids in input order', () async {
      final a = newMemory();
      final b = newMemory();
      final outcome = await store.insertCaptured([a, b], now);

      expect(outcome.insertedIds, [a.id, b.id]);
      expect(outcome.duplicates, isEmpty);
      final memory = (await store.getMemory(b.id))!;
      expect(memory.status, ProcessingStatus.captured);
      expect(memory.addedAt, now);
      expect(memory.updatedAt, now);
      expect(memory.attempts, 0);
    });

    test('skips hashes already stored or repeated in the batch', () async {
      final existing = newMemory();
      await store.insertCaptured([existing], now);

      final again = newMemory(sha256: existing.sha256);
      final fresh = newMemory();
      final copy = newMemory(sha256: fresh.sha256);
      final outcome = await store.insertCaptured([again, fresh, copy], now);

      expect(outcome.insertedIds, [fresh.id]);
      expect(outcome.duplicates, [again, copy]);
      expect(await store.getMemory(again.id), isNull);
      expect(await store.getMemory(copy.id), isNull);
      expect(scalar(db, 'SELECT COUNT(*) FROM memories'), 2);
    });
  });

  group('reading memories', () {
    test('getMemory round-trips every field', () async {
      final takenAt = DateTime(2026, 8, 31, 18, 30, 15, 123);
      final input = NewMemory(
        id: 'm1',
        imagePath: 'originals/m1.jpg',
        source: MemorySource.share,
        sha256: 'abc123',
        mimeType: 'image/jpeg',
        width: 1440,
        height: 3200,
        byteSize: 482133,
        takenAt: takenAt,
      );
      await store.insertCaptured([input], now);
      db.connection.execute(
        'UPDATE memories SET thumbnail_path = ?, summary = ?, '
        'visual_description = ?, extracted_text = ?, category = ?, '
        'attempts = 2, failure_reason = ?, processed_at = ?, '
        'last_viewed_at = ?, status = ? WHERE id = ?',
        [
          'thumbnails/m1.webp',
          'A bill',
          'A screen',
          'Total 1842',
          'utility_bill',
          'Timed out',
          now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
          now.add(const Duration(hours: 2)).millisecondsSinceEpoch,
          'failed',
          'm1',
        ],
      );

      final memory = (await store.getMemory('m1'))!;
      expect(memory.id, 'm1');
      expect(memory.imagePath, 'originals/m1.jpg');
      expect(memory.thumbnailPath, 'thumbnails/m1.webp');
      expect(memory.source, MemorySource.share);
      expect(memory.sha256, 'abc123');
      expect(memory.mimeType, 'image/jpeg');
      expect(memory.width, 1440);
      expect(memory.height, 3200);
      expect(memory.byteSize, 482133);
      expect(memory.takenAt.isUtc, isTrue);
      expect(
        memory.takenAt.millisecondsSinceEpoch,
        takenAt.millisecondsSinceEpoch,
      );
      expect(memory.addedAt, now);
      expect(memory.updatedAt, now);
      expect(memory.status, ProcessingStatus.failed);
      expect(memory.summary, 'A bill');
      expect(memory.visualDescription, 'A screen');
      expect(memory.extractedText, 'Total 1842');
      expect(memory.category, 'utility_bill');
      expect(memory.attempts, 2);
      expect(memory.failureReason, 'Timed out');
      expect(memory.processedAt, now.add(const Duration(hours: 1)));
      expect(memory.lastViewedAt, now.add(const Duration(hours: 2)));
    });

    test('getMemory returns null for an unknown id', () async {
      expect(await store.getMemory('nope'), isNull);
    });

    test('getMemories keeps input order and skips missing ids', () async {
      final a = await seedMemory(db);
      final b = await seedMemory(db);
      final c = await seedMemory(db);

      final memories = await store.getMemories([c, 'missing', a, b]);
      expect(memories.map((m) => m.id), [c, a, b]);
      expect(await store.getMemories(const []), isEmpty);
    });
  });

  group('saveUnderstanding', () {
    test('writes AI fields and leaves status alone', () async {
      final id = await seedMemory(db);
      final later = now.add(const Duration(minutes: 5));
      await store.saveUnderstanding(id, understanding(), facts(), later);

      final memory = (await store.getMemory(id))!;
      expect(memory.summary, 'Reliance electricity bill for August 2026');
      expect(memory.visualDescription, contains('utility bill'));
      expect(memory.extractedText, contains('Amount due'));
      expect(memory.category, 'utility_bill');
      expect(memory.status, ProcessingStatus.captured);
      expect(memory.updatedAt, later);
    });

    test('stores blank text fields as null', () async {
      final id = await seedMemory(db);
      await store.saveUnderstanding(
        id,
        understanding(visualDescription: '', extractedText: '  '),
        facts(),
        now,
      );

      final memory = (await store.getMemory(id))!;
      expect(memory.visualDescription, isNull);
      expect(memory.extractedText, isNull);
    });

    test('replaces entities, attributes and keywords', () async {
      final id = await seedMemory(db);
      await store.saveUnderstanding(
        id,
        understanding(),
        facts(
          entities: [entity('company', 'Reliance'), entity('person', 'Asha')],
          attributes: [amount(1842), dateAttribute('due_date', '2026-08-31')],
          keywords: ['reliance', 'bill'],
        ),
        now,
      );
      await store.saveUnderstanding(
        id,
        understanding(summary: 'Airtel bill', keywords: const ['airtel']),
        facts(
          entities: [entity('company', 'Airtel')],
          attributes: [amount(499)],
          keywords: ['airtel', 'airtel', 'mobile'],
        ),
        now,
      );

      final details = (await store.getDetails(id))!;
      expect(details.entities.map((e) => e.value), ['Airtel']);
      expect(details.attributes.map((a) => a.valueNum), [499]);
      expect(details.keywords, ['airtel', 'mobile']);
    });

    test('keeps exactly one FTS row in step with the memory', () async {
      final id = await seedMemory(db);
      final other = await seedMemory(db);
      await store.saveUnderstanding(
        id,
        understanding(summary: 'Old summary about gardening'),
        facts(keywords: ['gardening']),
        now,
      );
      await store.saveUnderstanding(
        id,
        understanding(),
        facts(
          entities: [entity('company', 'Reliance Energy')],
          keywords: ['electricity', 'bill'],
        ),
        now,
      );
      await store.saveUnderstanding(
        other,
        understanding(
          summary: 'Flight to Goa',
          category: 'booking',
          visualDescription: 'Boarding pass',
          extractedText: 'IndiGo 6E 204',
          keywords: const ['flight'],
        ),
        facts(keywords: ['flight']),
        now,
      );

      final seq = scalar(db, 'SELECT seq FROM memories WHERE id = ?', [id]);
      final rows = db.connection.select(
        'SELECT rowid, * FROM memories_fts WHERE rowid = ?',
        [seq],
      );
      expect(rows, hasLength(1));
      expect(rows.single['summary'], contains('electricity'));
      expect(rows.single['keywords'], 'electricity bill');
      expect(rows.single['entities'], 'Reliance Energy');
      expect(rows.single['extracted_text'], contains('Amount due'));
      expect(rows.single['visual_description'], contains('utility bill'));

      List<Object?> match(String query) => db.connection
          .select('SELECT rowid FROM memories_fts WHERE memories_fts MATCH ?', [
            query,
          ])
          .map((r) => r['rowid'] as Object?)
          .toList();
      expect(match('electricity'), [seq]);
      expect(match('gardening'), isEmpty);
      expect(scalar(db, 'SELECT COUNT(*) FROM memories_fts'), 2);
    });

    test('does nothing for a memory that no longer exists', () async {
      await store.saveUnderstanding(
        'gone',
        understanding(),
        facts(keywords: ['bill']),
        now,
      );
      expect(scalar(db, 'SELECT COUNT(*) FROM keywords'), 0);
      expect(scalar(db, 'SELECT COUNT(*) FROM memories_fts'), 0);
    });
  });

  group('getDetails', () {
    test('returns facts, processing history and citation count', () async {
      final id = await seedMemory(db);
      await store.saveUnderstanding(
        id,
        understanding(),
        facts(
          entities: [entity('company', 'Reliance')],
          attributes: [
            amount(1842, label: 'total'),
            dateAttribute('due_date', '2026-08-31'),
            textAttribute('account_number', '•••• 4471'),
          ],
          keywords: ['reliance', 'electricity'],
        ),
        now,
      );
      await store.addProcessingRecord(
        ProcessingRecord(
          memoryId: id,
          capability: Capability.vision,
          provider: 'groq',
          model: 'llama-4-scout',
          outcome: ProcessingOutcome.failed,
          latency: const Duration(milliseconds: 950),
          error: 'Timed out',
          createdAt: now,
        ),
      );
      await store.addProcessingRecord(
        ProcessingRecord(
          memoryId: id,
          capability: Capability.embeddings,
          provider: 'local',
          model: 'bge-small-en-v1.5',
          version: '1',
          outcome: ProcessingOutcome.succeeded,
          latency: const Duration(milliseconds: 40),
          createdAt: now.add(const Duration(minutes: 1)),
        ),
      );
      _cite(db, id, conversation: 'c1', message: 'msg1');
      _cite(db, id, conversation: 'c1', message: 'msg2');
      _cite(db, id, conversation: 'c2', message: 'msg3');

      final details = (await store.getDetails(id))!;
      expect(details.memory.id, id);

      final e = details.entities.single;
      expect(
        [e.type, e.value, e.normalizedValue],
        ['company', 'Reliance', 'reliance'],
      );

      expect(details.attributes, hasLength(3));
      final total = details.attributes[0];
      expect(total.type, 'amount');
      expect(total.valueNum, 1842);
      expect(total.currency, 'INR');
      expect(total.label, 'total');
      expect(total.valueDate, isNull);
      expect(details.attributes[1].valueDate, '2026-08-31');
      expect(details.attributes[1].valueNum, isNull);
      expect(details.attributes[2].value, '•••• 4471');

      expect(details.keywords, ['reliance', 'electricity']);

      expect(details.processing.map((r) => r.capability), [
        Capability.embeddings,
        Capability.vision,
      ]);
      final vision = details.processing.last;
      expect(vision.provider, 'groq');
      expect(vision.model, 'llama-4-scout');
      expect(vision.outcome, ProcessingOutcome.failed);
      expect(vision.latency, const Duration(milliseconds: 950));
      expect(vision.error, 'Timed out');
      expect(vision.version, isNull);
      expect(vision.createdAt, now);
      expect(details.processing.first.version, '1');

      expect(details.conversationCount, 2);
    });

    test('returns null for an unknown id', () async {
      expect(await store.getDetails('nope'), isNull);
    });
  });

  group('listMemories', () {
    late String july;
    late String august;
    late String september;
    late String unfiled;

    setUp(() async {
      july = await seedMemory(db, takenAt: DateTime.utc(2026, 7, 10));
      august = await seedMemory(db, takenAt: DateTime.utc(2026, 8, 10));
      september = await seedMemory(db, takenAt: DateTime.utc(2026, 9, 10));
      unfiled = await seedMemory(db, takenAt: DateTime.utc(2026, 6, 10));
      await store.saveUnderstanding(
        july,
        understanding(category: 'receipt'),
        facts(),
        now,
      );
      await store.saveUnderstanding(
        august,
        understanding(category: 'booking'),
        facts(),
        now,
      );
      await store.saveUnderstanding(
        september,
        understanding(category: 'receipt'),
        facts(),
        now,
      );
      setStatus(db, july, ProcessingStatus.ready);
      setStatus(db, august, ProcessingStatus.failed);
    });

    Future<List<String>> ids(MemoryListQuery query) async =>
        (await store.listMemories(query)).map((m) => m.id).toList();

    test('sorts newest and oldest by taken date', () async {
      expect(await ids(const MemoryListQuery()), [
        september,
        august,
        july,
        unfiled,
      ]);
      expect(await ids(const MemoryListQuery(sort: MemorySort.oldest)), [
        unfiled,
        july,
        august,
        september,
      ]);
    });

    test('sorts by category with uncategorized last', () async {
      expect(await ids(const MemoryListQuery(sort: MemorySort.category)), [
        august,
        september,
        july,
        unfiled,
      ]);
    });

    test('sorts recently viewed first with unviewed last', () async {
      await store.markViewed(july, now);
      await store.markViewed(unfiled, now.add(const Duration(minutes: 1)));
      expect(
        await ids(const MemoryListQuery(sort: MemorySort.recentlyViewed)),
        [unfiled, july, september, august],
      );
    });

    test('filters by category, status and taken date', () async {
      expect(await ids(const MemoryListQuery(categories: {'receipt'})), [
        september,
        july,
      ]);
      expect(
        await ids(
          const MemoryListQuery(
            statuses: {ProcessingStatus.ready, ProcessingStatus.failed},
          ),
        ),
        [august, july],
      );
      expect(
        await ids(
          MemoryListQuery(
            takenBetween: DateRange(
              start: DateTime.utc(2026, 7),
              end: DateTime.utc(2026, 9),
            ),
          ),
        ),
        [august, july],
      );
      expect(
        await ids(
          MemoryListQuery(
            categories: const {'receipt'},
            takenBetween: DateRange(start: DateTime.utc(2026, 8)),
          ),
        ),
        [september],
      );
    });

    test('pages with offset and limit', () async {
      expect(await ids(const MemoryListQuery(offset: 1, limit: 2)), [
        august,
        july,
      ]);
      expect(await ids(const MemoryListQuery(offset: 4)), isEmpty);
    });
  });

  group('counts', () {
    test(
      'categoryCounts ignores nulls and orders by count then name',
      () async {
        Future<void> filed(String category) async {
          final id = await seedMemory(db);
          await store.saveUnderstanding(
            id,
            understanding(category: category),
            facts(),
            now,
          );
        }

        await filed('receipt');
        await filed('booking');
        await filed('utility_bill');
        await filed('utility_bill');
        await filed('chat');
        await seedMemory(db);

        final counts = await store.categoryCounts();
        expect(counts.map((c) => '${c.value}:${c.count}'), [
          'utility_bill:2',
          'booking:1',
          'chat:1',
          'receipt:1',
        ]);
      },
    );

    test('queueSummary counts by status', () async {
      const statuses = [
        ProcessingStatus.captured,
        ProcessingStatus.captured,
        ProcessingStatus.reprocessing,
        ProcessingStatus.processing,
        ProcessingStatus.ready,
        ProcessingStatus.ready,
        ProcessingStatus.ready,
        ProcessingStatus.failed,
      ];
      for (final status in statuses) {
        setStatus(db, await seedMemory(db), status);
      }

      final summary = await store.queueSummary();
      expect(summary.total, 8);
      expect(summary.waiting, 3);
      expect(summary.processing, 1);
      expect(summary.ready, 3);
      expect(summary.failed, 1);
    });

    test('queueSummary is all zeros for an empty database', () async {
      final summary = await store.queueSummary();
      expect(
        [
          summary.total,
          summary.waiting,
          summary.processing,
          summary.ready,
          summary.failed,
        ],
        [0, 0, 0, 0, 0],
      );
    });

    test('storageStats sums image bytes', () async {
      expect((await store.storageStats()).imageBytes, 0);
      await seedMemory(db, byteSize: 1500);
      await seedMemory(db, byteSize: 2500);

      final stats = await store.storageStats();
      expect(stats.memoryCount, 2);
      expect(stats.imageBytes, 4000);
    });
  });

  group('deleting', () {
    test('deleteMemory removes the memory and everything derived', () async {
      final id = await seedMemory(db);
      final keep = await seedMemory(db);
      await store.setThumbnail(id, 'thumbnails/x.webp', now);
      for (final memoryId in [id, keep]) {
        await store.saveUnderstanding(
          memoryId,
          understanding(),
          facts(
            entities: [entity('company', 'Reliance')],
            attributes: [amount(1842)],
            keywords: ['bill'],
          ),
          now,
        );
        _embed(db, memoryId);
      }
      await store.addProcessingRecord(
        ProcessingRecord(
          memoryId: id,
          capability: Capability.vision,
          provider: 'local',
          model: 'ocr',
          outcome: ProcessingOutcome.succeeded,
          createdAt: now,
        ),
      );
      _cite(db, id, conversation: 'c1', message: 'msg1');

      final files = await store.deleteMemory(id);
      expect(files!.imagePath, 'originals/$id.png');
      expect(files.thumbnailPath, 'thumbnails/x.webp');
      expect(await store.getMemory(id), isNull);

      for (final table in [
        'entities',
        'attributes',
        'keywords',
        'embeddings',
        'processing_metadata',
        'message_references',
      ]) {
        expect(
          scalar(db, 'SELECT COUNT(*) FROM $table WHERE memory_id = ?', [id]),
          0,
          reason: table,
        );
      }
      expect(scalar(db, 'SELECT COUNT(*) FROM memories_fts'), 1);
      expect(scalar(db, 'SELECT COUNT(*) FROM messages'), 1);
      expect(await store.getDetails(keep), isNotNull);
      expect(scalar(db, 'SELECT COUNT(*) FROM keywords'), 1);
    });

    test('deleteMemory returns null for an unknown id', () async {
      expect(await store.deleteMemory('nope'), isNull);
    });

    test('deleteAll returns every file and keeps conversations', () async {
      final a = await seedMemory(db);
      final b = await seedMemory(db);
      await store.setThumbnail(b, 'thumbnails/b.webp', now);
      for (final id in [a, b]) {
        await store.saveUnderstanding(
          id,
          understanding(),
          facts(
            entities: [entity('company', 'Reliance')],
            attributes: [amount(10)],
            keywords: ['bill'],
          ),
          now,
        );
        _embed(db, id);
      }
      _cite(db, a, conversation: 'c1', message: 'msg1');

      final files = await store.deleteAll();
      expect(files.map((f) => f.all), [
        ['originals/$a.png'],
        ['originals/$b.png', 'thumbnails/b.webp'],
      ]);
      for (final table in [
        'memories',
        'memories_fts',
        'entities',
        'attributes',
        'keywords',
        'embeddings',
        'processing_metadata',
        'message_references',
      ]) {
        expect(scalar(db, 'SELECT COUNT(*) FROM $table'), 0, reason: table);
      }
      expect(scalar(db, 'SELECT COUNT(*) FROM conversations'), 1);
      expect(scalar(db, 'SELECT COUNT(*) FROM messages'), 1);
    });
  });

  group('thumbnails, views and processing records', () {
    test('missingThumbnails lists oldest added first', () async {
      final first = await seedMemory(db, now: now);
      final second = await seedMemory(
        db,
        now: now.add(const Duration(minutes: 1)),
      );
      final third = await seedMemory(
        db,
        now: now.add(const Duration(minutes: 2)),
      );
      await store.setThumbnail(
        second,
        'thumbnails/2.webp',
        now.add(const Duration(hours: 1)),
      );

      final missing = await store.missingThumbnails();
      expect(missing.map((m) => m.id), [first, third]);
      expect((await store.missingThumbnails(limit: 1)).single.id, first);

      final updated = (await store.getMemory(second))!;
      expect(updated.thumbnailPath, 'thumbnails/2.webp');
      expect(updated.updatedAt, now.add(const Duration(hours: 1)));
    });

    test('markViewed sets last viewed time', () async {
      final id = await seedMemory(db);
      expect((await store.getMemory(id))!.lastViewedAt, isNull);
      await store.markViewed(id, now);
      expect((await store.getMemory(id))!.lastViewedAt, now);
    });

    test('addProcessingRecord ignores memories that are gone', () async {
      await store.addProcessingRecord(
        ProcessingRecord(
          memoryId: 'gone',
          capability: Capability.vision,
          provider: 'local',
          model: 'ocr',
          outcome: ProcessingOutcome.succeeded,
          createdAt: now,
        ),
      );
      expect(scalar(db, 'SELECT COUNT(*) FROM processing_metadata'), 0);
    });
  });

  group('dataVersion', () {
    test('changes after a commit from another connection', () async {
      final path = tempDatabasePath();
      final ui = MemoraDatabase.open(path);
      addTearDown(ui.close);
      final worker = MemoraDatabase.open(path);
      addTearDown(worker.close);

      final before = await ui.memories.dataVersion();
      expect(await ui.memories.dataVersion(), before);

      await worker.memories.insertCaptured([newMemory()], now);
      final after = await ui.memories.dataVersion();
      expect(after, isNot(before));
      expect(await ui.memories.dataVersion(), after);
    });

    test('changes after a commit on the same connection', () async {
      final before = await store.dataVersion();
      await seedMemory(db);
      expect(await store.dataVersion(), isNot(before));
    });
  });
}

/// Arranges a conversation message that cites [memoryId], with raw SQL.
void _cite(
  MemoraDatabase db,
  String memoryId, {
  required String conversation,
  required String message,
}) {
  db.connection
    ..execute(
      'INSERT OR IGNORE INTO conversations (id, title, created_at, updated_at) '
      "VALUES (?, 'Bills', 0, 0)",
      [conversation],
    )
    ..execute(
      'INSERT INTO messages (id, conversation_id, role, content, created_at) '
      "VALUES (?, ?, 'assistant', 'Here', 0)",
      [message, conversation],
    )
    ..execute(
      'INSERT INTO message_references (message_id, memory_id, position) '
      'VALUES (?, ?, 0)',
      [message, memoryId],
    );
}

/// Arranges a stored vector for [memoryId], with raw SQL.
void _embed(MemoraDatabase db, String memoryId) {
  db.connection.execute(
    'INSERT INTO embeddings (memory_id, vector, model_id, model_version, '
    "dimensions, created_at) VALUES (?, ?, 'local/bge', '1', 1, 0)",
    [
      memoryId,
      [0, 0, 128, 63],
    ],
  );
}
