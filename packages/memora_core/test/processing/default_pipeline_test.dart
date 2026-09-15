import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

import '../fakes/fake_stores.dart';

const _bill = MemoryUnderstanding(
  summary: 'Reliance electricity bill for August 2026',
  category: 'utility_bill',
  visualDescription: 'A utility bill in a mobile app.',
  extractedText: 'Amount due Rs 1,842',
  keywords: ['reliance', 'electricity', 'bill'],
  entities: [EntityMention(type: 'company', value: 'Reliance')],
  dates: [DateMention(type: 'due_date', value: '2026-08-31')],
  amounts: [AmountMention(type: 'total', value: 1842, currency: 'INR')],
);

/// Vision that moves the fake clock forward on every call, to test budgets.
class _SlowVision implements VisionService {
  _SlowVision(this.clock, this.step);

  final FixedClock clock;
  final Duration step;
  int calls = 0;

  @override
  Future<MemoryUnderstanding> analyze(VisionRequest request) async {
    calls++;
    clock.advance(step);
    return _bill;
  }

  @override
  Future<VerificationResult> verify(VerificationRequest request) =>
      throw UnimplementedError();
}

void main() {
  late FakeMemora db;
  late FakeImageFiles images;
  late FixedClock clock;
  late InMemorySettingsStore settings;
  late QueuePolicyRepository policy;

  setUp(() async {
    db = FakeMemora();
    images = FakeImageFiles();
    clock = FixedClock(DateTime(2026, 9, 15, 2));
    settings = InMemorySettingsStore();
    policy = QueuePolicyRepository(settings);
  });

  DefaultProcessingPipeline pipelineFor(AiHarness ai) =>
      DefaultProcessingPipeline(
        queue: db,
        memories: db,
        vectors: db,
        router: ai.router,
        images: images,
        policy: policy,
        clock: clock,
      );

  void seedCaptured(String id, {DateTime? takenAt}) => db.seed(
    id: id,
    status: ProcessingStatus.captured,
    takenAt: takenAt ?? DateTime(2026, 9, 1),
  );

  group('processNext', () {
    test('stores facts, a vector and processing records', () async {
      final vision = ScriptedVisionService(analyze: [_bill]);
      final embeddings = FakeEmbeddingService();
      final ai = await AiHarness.create(vision: vision, embeddings: embeddings);
      seedCaptured('m1');

      final outcome = await pipelineFor(ai).processNext();

      expect(
        outcome,
        isA<Processed>()
            .having((p) => p.memoryId, 'memoryId', 'm1')
            .having((p) => p.status, 'status', ProcessingStatus.ready),
      );
      final details = (await db.getDetails('m1'))!;
      expect(details.memory.status, ProcessingStatus.ready);
      expect(details.memory.category, 'utility_bill');
      expect(details.memory.processedAt, clock.current);
      expect(details.entities.single.normalizedValue, 'reliance');
      expect(details.attributes.map((a) => a.value), ['₹1,842', '31 Aug 2026']);
      expect(await db.countFor(embeddings.model), 1);

      final request = vision.analyzeRequests.single;
      expect(request.absoluteImagePath, '/data/files/originals/m1.png');
      expect(request.mimeType, 'image/png');
      expect(request.takenAt, DateTime(2026, 9, 1));
      expect(request.defaultCurrency, 'INR');

      final facts = const FactNormalizer().normalize(
        _bill,
        takenAt: DateTime(2026, 9, 1),
      );
      expect(embeddings.calls.single, [buildEmbeddingText(_bill, facts)]);
      expect(embeddings.purposes.single, EmbeddingPurpose.document);

      final records = details.processing;
      final visionRecord = records.firstWhere(
        (r) => r.capability == Capability.vision,
      );
      expect(visionRecord.outcome, ProcessingOutcome.succeeded);
      expect(visionRecord.provider, 'fake');
      expect(visionRecord.model, 'vision-model');
      expect(visionRecord.latency, isNotNull);
      final embeddingRecord = records.firstWhere(
        (r) => r.capability == Capability.embeddings,
      );
      expect(embeddingRecord.outcome, ProcessingOutcome.succeeded);
      expect(embeddingRecord.model, 'embedding-model');
      expect(embeddingRecord.version, '1');
    });

    test('returns QueueEmpty when nothing is due', () async {
      final ai = await AiHarness.create(vision: ScriptedVisionService());
      expect(await pipelineFor(ai).processNext(), isA<QueueEmpty>());
    });

    test('transient errors back off, then fail after three attempts', () async {
      final vision = ScriptedVisionService(
        analyze: [
          const AiTransientException('Timed out'),
          const AiTransientException('Timed out'),
          const AiTransientException('Rate limited'),
        ],
      );
      final ai = await AiHarness.create(vision: vision);
      final pipeline = pipelineFor(ai);
      seedCaptured('m1');

      var outcome = await pipeline.processNext();
      expect((outcome as Processed).status, ProcessingStatus.captured);
      var row = db.rows['m1']!;
      expect(row.attempts, 1);
      expect(row.nextAttemptAt, clock.current.add(const Duration(minutes: 1)));
      expect(row.failureReason, 'Timed out');
      expect(await pipeline.processNext(), isA<QueueEmpty>());

      clock.advance(const Duration(minutes: 2));
      outcome = await pipeline.processNext();
      expect((outcome as Processed).status, ProcessingStatus.captured);
      row = db.rows['m1']!;
      expect(row.attempts, 2);
      expect(row.nextAttemptAt, clock.current.add(const Duration(minutes: 5)));

      clock.advance(const Duration(minutes: 6));
      outcome = await pipeline.processNext();
      expect((outcome as Processed).status, ProcessingStatus.failed);
      expect(db.rows['m1']!.status, ProcessingStatus.failed);
      expect(db.rows['m1']!.failureReason, 'Rate limited');

      final records = (await db.getDetails('m1'))!.processing;
      expect(records, hasLength(3));
      expect(
        records.every((r) => r.outcome == ProcessingOutcome.failed),
        isTrue,
      );
      expect(records.first.error, 'Rate limited');
    });

    test('a longer retry-after from the provider wins over backoff', () async {
      final ai = await AiHarness.create(
        vision: ScriptedVisionService(
          analyze: [
            const AiTransientException(
              'Slow down',
              retryAfter: Duration(minutes: 3),
            ),
          ],
        ),
      );
      seedCaptured('m1');

      await pipelineFor(ai).processNext();

      expect(
        db.rows['m1']!.nextAttemptAt,
        clock.current.add(const Duration(minutes: 3)),
      );
    });

    test(
      'configuration errors block the queue and give the attempt back',
      () async {
        final ai = await AiHarness.create(
          vision: ScriptedVisionService(
            analyze: [
              const AiConfigurationException('The API key was rejected'),
            ],
          ),
        );
        seedCaptured('m1');

        final outcome = await pipelineFor(ai).processNext();

        expect(
          outcome,
          isA<QueueBlocked>().having(
            (b) => b.block,
            'block',
            isA<ProviderConfigurationProblem>()
                .having((p) => p.providerName, 'providerName', 'Fake AI')
                .having(
                  (p) => p.message,
                  'message',
                  'The API key was rejected',
                ),
          ),
        );
        final row = db.rows['m1']!;
        expect(row.status, ProcessingStatus.captured);
        expect(row.attempts, 0);
        expect(
          (await db.getDetails('m1'))!.processing.single.outcome,
          ProcessingOutcome.failed,
        );
      },
    );

    test('content and format errors fail right away', () async {
      final ai = await AiHarness.create(
        vision: ScriptedVisionService(
          analyze: [
            const AiContentException('The provider refused this image'),
            const FormatException('Not JSON'),
          ],
        ),
      );
      final pipeline = pipelineFor(ai);
      seedCaptured('m1', takenAt: DateTime(2026, 9, 1));
      seedCaptured('m2', takenAt: DateTime(2026, 9, 2));

      expect(
        (await pipeline.processNext() as Processed).status,
        ProcessingStatus.failed,
      );
      expect(db.rows['m1']!.failureReason, 'The provider refused this image');
      expect(
        (await pipeline.processNext() as Processed).status,
        ProcessingStatus.failed,
      );
      expect(db.rows['m2']!.status, ProcessingStatus.failed);
    });

    test('an unreadable image file fails the memory', () async {
      final vision = ScriptedVisionService(analyze: [_bill]);
      final ai = await AiHarness.create(vision: vision);
      seedCaptured('m1');
      images.missing.add('originals/m1.png');

      final outcome = await pipelineFor(ai).processNext();

      expect((outcome as Processed).status, ProcessingStatus.failed);
      expect(db.rows['m1']!.failureReason, 'The image file could not be read.');
      expect(vision.analyzeRequests, isEmpty);
    });

    test('marks ready without an embeddings capability', () async {
      final ai = await AiHarness.create(
        vision: ScriptedVisionService(analyze: [_bill]),
      );
      seedCaptured('m1');

      final outcome = await pipelineFor(ai).processNext();

      expect((outcome as Processed).status, ProcessingStatus.ready);
      final records = (await db.getDetails('m1'))!.processing;
      expect(records.map((r) => r.capability), [Capability.vision]);
    });

    test(
      'an embedding failure is recorded and the memory is still ready',
      () async {
        final embeddings = FakeEmbeddingService()
          ..failWith = const AiTransientException('Embedding service down');
        final ai = await AiHarness.create(
          vision: ScriptedVisionService(analyze: [_bill]),
          embeddings: embeddings,
        );
        seedCaptured('m1');

        final outcome = await pipelineFor(ai).processNext();

        expect((outcome as Processed).status, ProcessingStatus.ready);
        final record = (await db.getDetails('m1'))!.processing
            .firstWhere((r) => r.capability == Capability.embeddings);
        expect(record.outcome, ProcessingOutcome.failed);
        expect(record.error, 'Embedding service down');
        expect(await db.countFor(embeddings.model), 0);
      },
    );

    test('local-only mode blocks without claiming anything', () async {
      final ai = await AiHarness.create(
        vision: ScriptedVisionService(analyze: [_bill]),
        location: ProviderLocation.cloud,
        localOnly: true,
      );
      seedCaptured('m1');

      final outcome = await pipelineFor(ai).processNext();

      expect(
        outcome,
        isA<QueueBlocked>().having(
          (b) => (b.block as BlockedByLocalOnly).providerName,
          'providerName',
          'Fake AI',
        ),
      );
      expect(db.rows['m1']!.status, ProcessingStatus.captured);
      expect(db.rows['m1']!.attempts, 0);
    });

    test('reports a missing provider and a missing key', () async {
      final none = await AiHarness.create();
      seedCaptured('m1');
      expect(
        (await pipelineFor(none).processNext() as QueueBlocked).block,
        isA<NoVisionProvider>(),
      );

      final keyless = await AiHarness.create(
        vision: ScriptedVisionService(),
        location: ProviderLocation.cloud,
        requiresApiKey: true,
      );
      final block =
          (await pipelineFor(keyless).processNext() as QueueBlocked).block
              as ProviderConfigurationProblem;
      expect(block.message, 'Add an API key for Fake AI');
      expect(db.rows['m1']!.attempts, 0);
    });
  });

  group('currentBlock', () {
    test('is null when vision is available', () async {
      final ai = await AiHarness.create(vision: ScriptedVisionService());
      expect(await pipelineFor(ai).currentBlock(), isNull);
    });

    test('explains why vision is unavailable', () async {
      final ai = await AiHarness.create();
      expect(await pipelineFor(ai).currentBlock(), isA<NoVisionProvider>());
    });
  });

  group('runQueue', () {
    test(
      'processes everything in immediate mode and reports no work left',
      () async {
        await policy.save(const QueuePolicy(mode: QueueMode.immediate));
        final ai = await AiHarness.create(
          vision: ScriptedVisionService(analyze: [_bill, _bill, _bill]),
        );
        for (final id in ['a', 'b', 'c']) {
          seedCaptured(id);
        }

        final report = await pipelineFor(ai)
            .runQueue(budget: const Duration(minutes: 9));

        expect(report.processed, 3);
        expect(report.remaining, isFalse);
        expect(report.block, isNull);
      },
    );

    test('does nothing while paused', () async {
      await policy.save(
        const QueuePolicy(mode: QueueMode.immediate, paused: true),
      );
      final vision = ScriptedVisionService(analyze: [_bill]);
      final ai = await AiHarness.create(vision: vision);
      seedCaptured('a');

      final report = await pipelineFor(ai)
          .runQueue(budget: const Duration(minutes: 9), processNow: true);

      expect(report.processed, 0);
      expect(report.remaining, isTrue);
      expect(vision.analyzeRequests, isEmpty);
    });

    test(
      'overnight mode waits for the window unless told to process now',
      () async {
        clock.current = DateTime(2026, 9, 15, 12);
        final ai = await AiHarness.create(
          vision: ScriptedVisionService(analyze: [_bill]),
        );
        seedCaptured('a');
        final pipeline = pipelineFor(ai);

        var report = await pipeline.runQueue(
          budget: const Duration(minutes: 9),
        );
        expect(report.processed, 0);
        expect(report.remaining, isTrue);

        report = await pipeline.runQueue(
          budget: const Duration(minutes: 9),
          processNow: true,
        );
        expect(report.processed, 1);
        expect(report.remaining, isFalse);
      },
    );

    test('stops when the budget runs out', () async {
      await policy.save(const QueuePolicy(mode: QueueMode.immediate));
      final vision = _SlowVision(clock, const Duration(minutes: 5));
      final ai = await AiHarness.create(vision: vision);
      for (final id in ['a', 'b', 'c']) {
        seedCaptured(id);
      }

      final report = await pipelineFor(ai)
          .runQueue(budget: const Duration(minutes: 9));

      expect(report.processed, 2);
      expect(report.remaining, isTrue);
      expect(vision.calls, 2);
    });

    test('stops and reports a block', () async {
      await policy.save(const QueuePolicy(mode: QueueMode.immediate));
      final ai = await AiHarness.create();
      seedCaptured('a');

      final report = await pipelineFor(ai)
          .runQueue(budget: const Duration(minutes: 9));

      expect(report.processed, 0);
      expect(report.block, isA<NoVisionProvider>());
      expect(report.remaining, isTrue);
    });
  });

  group('reindexEmbeddings', () {
    test(
      'embeds ready memories missing a vector in batches of eight',
      () async {
        final embeddings = FakeEmbeddingService();
        final ai = await AiHarness.create(embeddings: embeddings);
        for (var i = 0; i < 10; i++) {
          db.seed(id: 'r$i', summary: 'Memory $i', category: 'other');
        }
        db.seed(id: 'waiting', status: ProcessingStatus.captured);

        final count = await pipelineFor(ai)
            .reindexEmbeddings(budget: const Duration(minutes: 5));

        expect(count, 10);
        expect(embeddings.calls.map((c) => c.length), [8, 2]);
        expect(await db.countFor(embeddings.model), 10);
        expect(embeddings.calls.first.first, 'Memory 0\nCategory: other');
      },
    );

    test('returns zero without an embeddings capability', () async {
      final ai = await AiHarness.create();
      db.seed(id: 'r1');
      expect(
        await pipelineFor(ai)
            .reindexEmbeddings(budget: const Duration(minutes: 5)),
        0,
      );
    });

    test('gives up on memories that keep failing instead of looping', () async {
      final embeddings = FakeEmbeddingService()
        ..failWith = const AiContentException('Input too long');
      final ai = await AiHarness.create(embeddings: embeddings);
      for (var i = 0; i < 3; i++) {
        db.seed(id: 'r$i');
      }

      final count = await pipelineFor(ai)
          .reindexEmbeddings(budget: const Duration(minutes: 5));

      expect(count, 0);
      expect(embeddings.calls, hasLength(1));
    });
  });
}
