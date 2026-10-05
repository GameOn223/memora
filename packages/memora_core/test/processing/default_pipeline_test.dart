import 'dart:typed_data';

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

/// A cloud embedding service that only learns its dimensions from the first
/// response, as the OpenAI-compatible adapter does for unknown models.
class _LateDimensionsEmbeddings implements EmbeddingService {
  static const unknown = EmbeddingModelInfo(
    provider: 'fake',
    modelId: 'cloud-embed',
    version: '1',
    dimensions: 0,
  );
  static const known = EmbeddingModelInfo(
    provider: 'fake',
    modelId: 'cloud-embed',
    version: '1',
    dimensions: 8,
  );

  bool answered = false;
  int calls = 0;

  @override
  EmbeddingModelInfo get model => answered ? known : unknown;

  @override
  Future<List<Float32List>> embed(
    List<String> texts, {
    EmbeddingPurpose purpose = EmbeddingPurpose.document,
  }) async {
    calls++;
    answered = true;
    return [for (final _ in texts) Float32List(known.dimensions)..[0] = 1];
  }
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

    test('transient errors climb the backoff ladder, then fail', () async {
      final vision = ScriptedVisionService(
        analyze: [
          const AiTransientException('Timed out'),
          const AiTransientException('Timed out'),
          const AiTransientException('Timed out'),
          const AiTransientException('The provider is having trouble'),
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
      expect((outcome as Processed).status, ProcessingStatus.captured);
      row = db.rows['m1']!;
      expect(row.attempts, 3);
      expect(row.nextAttemptAt, clock.current.add(const Duration(minutes: 30)));

      clock.advance(const Duration(minutes: 31));
      outcome = await pipeline.processNext();
      expect((outcome as Processed).status, ProcessingStatus.failed);
      expect(db.rows['m1']!.status, ProcessingStatus.failed);
      expect(db.rows['m1']!.failureReason, 'The provider is having trouble');

      final records = (await db.getDetails('m1'))!.processing;
      expect(records, hasLength(4));
      expect(
        records.every((r) => r.outcome == ProcessingOutcome.failed),
        isTrue,
      );
      expect(records.first.error, 'The provider is having trouble');
    });

    test('the provider retry hint replaces the backoff ladder', () async {
      final ai = await AiHarness.create(
        vision: ScriptedVisionService(
          analyze: [
            const AiTransientException(
              'Slow down',
              retryAfter: Duration(minutes: 3),
            ),
            const AiTransientException(
              'Slow down',
              retryAfter: Duration(seconds: 10),
            ),
            const AiTransientException(
              'Slow down',
              retryAfter: Duration(hours: 9),
            ),
          ],
        ),
      );
      final pipeline = pipelineFor(ai);
      seedCaptured('m1');

      await pipeline.processNext();
      expect(
        db.rows['m1']!.nextAttemptAt,
        clock.current.add(const Duration(minutes: 3)),
        reason: 'the ladder would have said one minute',
      );

      clock.advance(const Duration(minutes: 4));
      await pipeline.processNext();
      expect(
        db.rows['m1']!.nextAttemptAt,
        clock.current.add(const Duration(seconds: 10)),
        reason: 'a shorter hint is honoured too, the ladder said five minutes',
      );

      clock.advance(const Duration(minutes: 1));
      await pipeline.processNext();
      expect(
        db.rows['m1']!.nextAttemptAt,
        clock.current.add(DefaultProcessingPipeline.maxRetryAfter),
        reason: 'a hint past the cap is clamped',
      );
    });

    test('a rate limit reschedules without spending an attempt', () async {
      final vision = ScriptedVisionService(
        analyze: [
          const AiRateLimitException(
            'Rate limited by the provider',
            retryAfter: Duration(minutes: 20),
          ),
          _bill,
        ],
      );
      final ai = await AiHarness.create(vision: vision);
      final pipeline = pipelineFor(ai);
      seedCaptured('m1');
      final retryAt = clock.current.add(const Duration(minutes: 20));

      final outcome = await pipeline.processNext();

      expect(
        outcome,
        isA<QueueBlocked>().having(
          (b) => b.block,
          'block',
          isA<RateLimited>()
              .having((r) => r.providerName, 'providerName', 'Fake AI')
              .having((r) => r.retryAt, 'retryAt', retryAt),
        ),
      );
      final row = db.rows['m1']!;
      expect(row.status, ProcessingStatus.captured);
      expect(
        row.attempts,
        0,
        reason: 'a rate limit is not the memory to blame',
      );
      expect(row.nextAttemptAt, retryAt);
      expect(row.failureReason, 'Rate limited by the provider');
      expect(
        (await db.getDetails('m1'))!.processing.single.outcome,
        ProcessingOutcome.failed,
      );

      expect(
        await pipeline.currentBlock(),
        isA<RateLimited>()
            .having((r) => r.providerName, 'providerName', 'Fake AI')
            .having(
              (r) => r.retryAt.millisecondsSinceEpoch,
              'retryAt',
              retryAt.millisecondsSinceEpoch,
            ),
      );

      // While the limit holds, nothing is claimed and the provider is left
      // alone.
      expect(
        (await pipeline.processNext() as QueueBlocked).block,
        isA<RateLimited>(),
      );
      expect(vision.analyzeRequests, hasLength(1));
      expect(db.rows['m1']!.attempts, 0);

      clock.advance(const Duration(minutes: 21));
      expect(await pipeline.currentBlock(), isNull);
      expect(
        (await pipeline.processNext() as Processed).status,
        ProcessingStatus.ready,
      );
      expect(db.rows['m1']!.attempts, 1, reason: 'only the real try counts');
      expect(await pipeline.currentBlock(), isNull);
      expect(
        settings.values.containsKey(QueuePolicyRepository.rateLimitKey),
        isFalse,
        reason: 'a success clears the note it left behind',
      );
    });

    test('a rate limit with no hint falls back to the ladder', () async {
      final ai = await AiHarness.create(
        vision: ScriptedVisionService(
          analyze: [const AiRateLimitException('Rate limited')],
        ),
      );
      seedCaptured('m1');

      final outcome = await pipelineFor(ai).processNext();

      expect((outcome as QueueBlocked).block, isA<RateLimited>());
      expect(
        db.rows['m1']!.nextAttemptAt,
        clock.current.add(const Duration(minutes: 1)),
      );
      expect(db.rows['m1']!.attempts, 0);
    });

    test('a rate limit never uses up the attempt cap', () async {
      final ai = await AiHarness.create(
        vision: ScriptedVisionService(
          analyze: [
            for (var i = 0; i < DefaultProcessingPipeline.maxAttempts + 2; i++)
              const AiRateLimitException(
                'Rate limited',
                retryAfter: Duration(minutes: 1),
              ),
          ],
        ),
      );
      final pipeline = pipelineFor(ai);
      seedCaptured('m1');

      for (var i = 0; i < DefaultProcessingPipeline.maxAttempts + 2; i++) {
        expect(
          (await pipeline.processNext() as QueueBlocked).block,
          isA<RateLimited>(),
        );
        expect(db.rows['m1']!.status, ProcessingStatus.captured);
        expect(db.rows['m1']!.attempts, 0);
        clock.advance(const Duration(minutes: 2));
      }
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

    test('content errors fail right away, unreadable output retries', () async {
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
        ProcessingStatus.captured,
        reason: 'broken structured output is usually a one-off',
      );
      expect(db.rows['m2']!.nextAttemptAt, isNotNull);
      expect(
        db.rows['m2']!.failureReason,
        'The provider returned data Memora could not read.',
      );
    });

    test('two engines at once never claim the same memory', () async {
      final ai = await AiHarness.create(
        vision: ScriptedVisionService(analyze: [_bill, _bill]),
      );
      seedCaptured('m1', takenAt: DateTime(2026, 9, 1));
      seedCaptured('m2', takenAt: DateTime(2026, 9, 2));

      final outcomes = await Future.wait([
        pipelineFor(ai).processNext(),
        pipelineFor(ai).processNext(),
      ]);

      expect(outcomes.whereType<Processed>().map((p) => p.memoryId).toSet(), {
        'm1',
        'm2',
      }, reason: 'the claim is atomic, so each engine gets its own row');
      expect(db.rows.values.map((r) => r.attempts), everyElement(1));
      expect(
        db.rows.values.map((r) => r.status),
        everyElement(ProcessingStatus.ready),
      );
    });

    test('a failing processing record never strands a memory', () async {
      final ai = await AiHarness.create(
        vision: ScriptedVisionService(
          analyze: [const AiTransientException('Timed out'), _bill],
        ),
      );
      final pipeline = pipelineFor(ai);
      seedCaptured('m1', takenAt: DateTime(2026, 9, 1));
      seedCaptured('m2', takenAt: DateTime(2026, 9, 2));
      db.failProcessingRecords = true;

      expect(
        (await pipeline.processNext() as Processed).status,
        ProcessingStatus.captured,
      );
      expect(db.rows['m1']!.status, ProcessingStatus.captured);
      expect(db.rows['m1']!.nextAttemptAt, isNotNull);

      expect(
        (await pipeline.processNext() as Processed).status,
        ProcessingStatus.ready,
      );
      expect(db.rows['m2']!.status, ProcessingStatus.ready);
      expect((await db.getDetails('m2'))!.processing, isEmpty);
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

    test('tags the vector with the dimensions the response reported', () async {
      final embeddings = _LateDimensionsEmbeddings();
      final ai = await AiHarness.create(
        vision: ScriptedVisionService(analyze: [_bill]),
        embeddings: embeddings,
      );
      seedCaptured('m1');

      final outcome = await pipelineFor(ai).processNext();

      expect((outcome as Processed).status, ProcessingStatus.ready);
      expect(await db.countFor(_LateDimensionsEmbeddings.known), 1);
      expect(await db.countFor(_LateDimensionsEmbeddings.unknown), 0);
      final record = (await db.getDetails('m1'))!.processing
          .firstWhere((r) => r.capability == Capability.embeddings);
      expect(record.outcome, ProcessingOutcome.succeeded);
    });

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

    test('claims nothing and calls no provider', () async {
      final vision = ScriptedVisionService(analyze: [_bill]);
      final ai = await AiHarness.create(vision: vision);
      seedCaptured('m1');

      expect(await pipelineFor(ai).currentBlock(), isNull);

      expect(vision.analyzeRequests, isEmpty);
      expect(db.rows['m1']!.status, ProcessingStatus.captured);
      expect(db.rows['m1']!.attempts, 0);
    });

    test('reports local-only mode and a missing key', () async {
      final blocked = await AiHarness.create(
        vision: ScriptedVisionService(),
        location: ProviderLocation.cloud,
        localOnly: true,
      );
      expect(
        await pipelineFor(blocked).currentBlock(),
        isA<BlockedByLocalOnly>().having(
          (b) => b.providerName,
          'providerName',
          'Fake AI',
        ),
      );

      final keyless = await AiHarness.create(
        vision: ScriptedVisionService(),
        location: ProviderLocation.cloud,
        requiresApiKey: true,
      );
      expect(
        await pipelineFor(keyless).currentBlock(),
        isA<ProviderConfigurationProblem>().having(
          (b) => b.message,
          'message',
          'Add an API key for Fake AI',
        ),
      );
    });

    test('names a selected provider with no service for the model', () async {
      final ai = await AiHarness.create(vision: ScriptedVisionService());
      ai.vision = null;

      expect(
        await pipelineFor(ai).currentBlock(),
        isA<ProviderUnavailable>()
            .having((b) => b.providerName, 'providerName', 'Fake AI')
            .having((b) => b.modelId, 'modelId', 'vision-model'),
      );
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

    test('memories waiting out a backoff still count as work', () async {
      await policy.save(const QueuePolicy(mode: QueueMode.immediate));
      final ai = await AiHarness.create(
        vision: ScriptedVisionService(
          analyze: [const AiTransientException('Timed out')],
        ),
      );
      seedCaptured('a');

      final report = await pipelineFor(ai)
          .runQueue(budget: const Duration(minutes: 9));

      expect(report.processed, 1);
      expect(
        report.remaining,
        isTrue,
        reason: 'the retry ladder needs the worker to come back',
      );
      expect(
        report.nextAttemptAt,
        clock.current.add(const Duration(minutes: 1)),
      );
      expect(
        await db.hasWork(clock.current),
        isFalse,
        reason: 'nothing is claimable yet, which is why hasWork is not enough',
      );
    });

    test('an empty queue reports no work and no retry', () async {
      await policy.save(const QueuePolicy(mode: QueueMode.immediate));
      final ai = await AiHarness.create(
        vision: ScriptedVisionService(analyze: [_bill]),
      );
      seedCaptured('a');

      final report = await pipelineFor(ai)
          .runQueue(budget: const Duration(minutes: 9));

      expect(report.remaining, isFalse);
      expect(report.nextAttemptAt, isNull);
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

    test('a rate limit stops the run and says when to come back', () async {
      await policy.save(const QueuePolicy(mode: QueueMode.immediate));
      final vision = ScriptedVisionService(
        analyze: [
          const AiRateLimitException(
            'Rate limited',
            retryAfter: Duration(minutes: 20),
          ),
          _bill,
        ],
      );
      final ai = await AiHarness.create(vision: vision);
      seedCaptured('a');
      seedCaptured('b');
      final retryAt = clock.current.add(const Duration(minutes: 20));

      final report = await pipelineFor(ai)
          .runQueue(budget: const Duration(minutes: 9));

      expect(report.processed, 0);
      expect(
        report.block,
        isA<RateLimited>().having((r) => r.retryAt, 'retryAt', retryAt),
      );
      expect(report.nextAttemptAt, retryAt);
      expect(report.remaining, isTrue);
      expect(
        vision.analyzeRequests,
        hasLength(1),
        reason: 'one rate limit is enough, the whole queue waits',
      );
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

    test('reindexing skips what a lazy model already has', () async {
      final embeddings = _LateDimensionsEmbeddings();
      final ai = await AiHarness.create(embeddings: embeddings);
      for (var i = 0; i < 3; i++) {
        db.seed(id: 'r$i', summary: 'Memory $i', category: 'other');
      }
      await db.upsert(
        'r0',
        Float32List(_LateDimensionsEmbeddings.known.dimensions)..[0] = 1,
        _LateDimensionsEmbeddings.known,
        clock.current,
      );

      final count = await pipelineFor(ai)
          .reindexEmbeddings(budget: const Duration(minutes: 5));

      expect(
        count,
        2,
        reason: 'the model learns its dimensions before the missing query',
      );
      expect(embeddings.calls, 2, reason: 'one warm-up, then one batch');
      expect(await db.countFor(_LateDimensionsEmbeddings.known), 3);
      expect(await db.countFor(_LateDimensionsEmbeddings.unknown), 0);
    });

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
