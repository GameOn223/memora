import 'dart:typed_data';

import '../ai/capabilities.dart';
import '../ai/errors.dart';
import '../ai/router.dart';
import '../model/memory.dart';
import '../model/processing.dart';
import '../ports/platform.dart';
import '../ports/stores.dart';
import '../services/contracts.dart';
import 'embedding_text.dart';
import 'fact_normalizer.dart';
import 'queue_policy_repository.dart';

/// Understands queued memories one at a time. See docs/architecture.md,
/// section 5.3.
class DefaultProcessingPipeline implements ProcessingPipeline {
  DefaultProcessingPipeline({
    required this._queue,
    required this._memories,
    required this._vectors,
    required this._router,
    required this._images,
    required this._policy,
    required this._clock,
    this._normalizer = const FactNormalizer(),
    this._lease = const Duration(minutes: 10),
    this._defaultCurrency = 'INR',
    this._localeTag = 'en-IN',
  });

  /// Attempts before a transient error fails a memory for good.
  static const maxAttempts = 3;

  /// How many memories are embedded per call while reindexing.
  static const reindexBatchSize = 8;

  final QueueStore _queue;
  final MemoryStore _memories;
  final VectorStore _vectors;
  final CapabilityRouter _router;
  final ImageFiles _images;
  final QueuePolicyRepository _policy;
  final Clock _clock;
  final FactNormalizer _normalizer;
  final Duration _lease;
  final String _defaultCurrency;
  final String _localeTag;

  /// Wait before retrying after a transient error, by attempts used so far.
  static Duration backoffFor(int attempts) => switch (attempts) {
    <= 1 => const Duration(minutes: 1),
    2 => const Duration(minutes: 5),
    _ => const Duration(minutes: 30),
  };

  @override
  Future<ProcessOutcome> processNext() async {
    final Resolved<VisionService> vision;
    try {
      vision = await _router.vision();
    } on CapabilityUnavailableException catch (e) {
      return QueueBlocked(blockFor(e));
    }

    final memory = await _queue.claimNext(_clock.now(), _lease);
    if (memory == null) return const QueueEmpty();

    final Uint8List bytes;
    try {
      bytes = await _images.readBytes(memory.imagePath);
    } on Exception catch (e) {
      await _record(memory.id, vision, ProcessingOutcome.failed, error: '$e');
      return _fail(memory, 'The image file could not be read.');
    }

    final stopwatch = Stopwatch()..start();
    try {
      final understanding = await vision.service.analyze(
        VisionRequest(
          imageBytes: bytes,
          mimeType: memory.mimeType,
          takenAt: memory.takenAt,
          absoluteImagePath: _images.absolutePath(memory.imagePath),
          defaultCurrency: _defaultCurrency,
          localeTag: _localeTag,
        ),
      );
      stopwatch.stop();
      final facts = _normalizer.normalize(
        understanding,
        defaultCurrency: _defaultCurrency,
        takenAt: memory.takenAt,
      );
      await _memories.saveUnderstanding(
        memory.id,
        understanding,
        facts,
        _clock.now(),
      );
      await _record(
        memory.id,
        vision,
        ProcessingOutcome.succeeded,
        latency: stopwatch.elapsed,
      );
      await _embed(memory.id, buildEmbeddingText(understanding, facts));
      await _queue.markReady(memory.id, _clock.now());
      return Processed(memory.id, ProcessingStatus.ready);
    } on AiConfigurationException catch (e) {
      await _record(
        memory.id,
        vision,
        ProcessingOutcome.failed,
        latency: stopwatch.elapsed,
        error: e.message,
      );
      await _queue.releaseWithoutAttempt(memory.id, _clock.now());
      return QueueBlocked(
        ProviderConfigurationProblem(vision.provider.displayName, e.message),
      );
    } on AiContentException catch (e) {
      await _record(
        memory.id,
        vision,
        ProcessingOutcome.failed,
        latency: stopwatch.elapsed,
        error: e.message,
      );
      return _fail(memory, e.message);
    } on FormatException catch (e) {
      await _record(
        memory.id,
        vision,
        ProcessingOutcome.failed,
        latency: stopwatch.elapsed,
        error: e.message,
      );
      return _fail(memory, 'The provider returned data Memora could not read.');
    } on AiTransientException catch (e) {
      await _record(
        memory.id,
        vision,
        ProcessingOutcome.failed,
        latency: stopwatch.elapsed,
        error: e.message,
      );
      return _retryOrFail(memory, e.message, retryAfter: e.retryAfter);
    } on Object catch (e) {
      // Anything unexpected is retried like a transient error, so a bug in
      // one adapter can't leave a memory stuck in processing.
      await _record(
        memory.id,
        vision,
        ProcessingOutcome.failed,
        latency: stopwatch.elapsed,
        error: '$e',
      );
      return _retryOrFail(
        memory,
        'Something went wrong while understanding this image.',
      );
    }
  }

  Future<ProcessOutcome> _retryOrFail(
    Memory memory,
    String reason, {
    Duration? retryAfter,
  }) async {
    if (memory.attempts >= maxAttempts) return _fail(memory, reason);
    final now = _clock.now();
    var wait = backoffFor(memory.attempts);
    if (retryAfter != null && retryAfter > wait) wait = retryAfter;
    await _queue.releaseForRetry(
      memory.id,
      nextAttemptAt: now.add(wait),
      reason: reason,
      now: now,
    );
    return Processed(memory.id, ProcessingStatus.captured);
  }

  Future<ProcessOutcome> _fail(Memory memory, String reason) async {
    await _queue.markFailed(memory.id, reason, _clock.now());
    return Processed(memory.id, ProcessingStatus.failed);
  }

  /// Embeds one memory. Unavailable embeddings are skipped quietly and
  /// failures are recorded, since neither should stop the memory being
  /// ready.
  Future<void> _embed(String memoryId, String text) async {
    final Resolved<EmbeddingService> embeddings;
    try {
      embeddings = await _router.embeddings();
    } on CapabilityUnavailableException {
      return;
    }
    final stopwatch = Stopwatch()..start();
    try {
      final vectors = await embeddings.service.embed([text]);
      stopwatch.stop();
      if (vectors.length != 1) {
        throw const FormatException('Expected one vector');
      }
      final model = embeddings.service.model;
      await _vectors.upsert(memoryId, vectors.single, model, _clock.now());
      await _record(
        memoryId,
        embeddings,
        ProcessingOutcome.succeeded,
        capability: Capability.embeddings,
        version: model.version,
        latency: stopwatch.elapsed,
      );
    } on Object catch (e) {
      await _record(
        memoryId,
        embeddings,
        ProcessingOutcome.failed,
        capability: Capability.embeddings,
        latency: stopwatch.elapsed,
        error: e is AiException ? e.message : '$e',
      );
    }
  }

  Future<void> _record(
    String memoryId,
    Resolved<Object> resolved,
    ProcessingOutcome outcome, {
    Capability capability = Capability.vision,
    String? version,
    Duration? latency,
    String? error,
  }) {
    return _memories.addProcessingRecord(
      ProcessingRecord(
        memoryId: memoryId,
        capability: capability,
        provider: resolved.provider.id,
        model: resolved.modelId,
        version: version,
        outcome: outcome,
        latency: latency,
        error: error,
        createdAt: _clock.now(),
      ),
    );
  }

  @override
  Future<QueueRunReport> runQueue({
    required Duration budget,
    bool processNow = false,
  }) async {
    final startedAt = _clock.now();
    final stopwatch = Stopwatch()..start();
    var processed = 0;
    QueueBlock? block;

    while (true) {
      final now = _clock.now();
      final policy = await _policy.load();
      if (!policy.allowsProcessingAt(now.toLocal(), processNow: processNow)) {
        break;
      }
      if (_elapsed(startedAt, stopwatch) >= budget) break;
      final outcome = await processNext();
      if (outcome is Processed) {
        processed++;
      } else if (outcome is QueueBlocked) {
        block = outcome.block;
        break;
      } else {
        break;
      }
    }

    return QueueRunReport(
      processed: processed,
      remaining: await _queue.hasWork(_clock.now()),
      block: block,
    );
  }

  /// The longer of wall time and injected clock time, so tests can move the
  /// clock and real runs still respect the budget.
  Duration _elapsed(DateTime startedAt, Stopwatch stopwatch) {
    final byClock = _clock.now().difference(startedAt);
    return byClock > stopwatch.elapsed ? byClock : stopwatch.elapsed;
  }

  @override
  Future<int> reindexEmbeddings({required Duration budget}) async {
    final Resolved<EmbeddingService> embeddings;
    try {
      embeddings = await _router.embeddings();
    } on CapabilityUnavailableException {
      return 0;
    }
    final service = embeddings.service;
    final startedAt = _clock.now();
    final stopwatch = Stopwatch()..start();
    final skipped = <String>{};
    var count = 0;

    while (_elapsed(startedAt, stopwatch) < budget) {
      final missing = await _vectors.missingFor(
        service.model,
        limit: skipped.length + reindexBatchSize,
      );
      final ids = missing
          .where((id) => !skipped.contains(id))
          .take(reindexBatchSize)
          .toList();
      if (ids.isEmpty) break;

      final targets = <String>[];
      final texts = <String>[];
      for (final id in ids) {
        final details = await _memories.getDetails(id);
        if (details == null) {
          skipped.add(id);
          continue;
        }
        targets.add(id);
        texts.add(embeddingTextForDetails(details));
      }
      if (targets.isEmpty) continue;

      final batchWatch = Stopwatch()..start();
      final List<Float32List> vectors;
      try {
        vectors = await service.embed(texts);
      } on AiTransientException {
        break;
      } on AiConfigurationException {
        break;
      } on Object catch (e) {
        skipped.addAll(targets);
        for (final id in targets) {
          await _record(
            id,
            embeddings,
            ProcessingOutcome.failed,
            capability: Capability.embeddings,
            error: e is AiException ? e.message : '$e',
          );
        }
        continue;
      }
      if (vectors.length != targets.length) {
        skipped.addAll(targets);
        continue;
      }
      final latency = batchWatch.elapsed ~/ targets.length;
      for (var i = 0; i < targets.length; i++) {
        await _vectors.upsert(
          targets[i],
          vectors[i],
          service.model,
          _clock.now(),
        );
        await _record(
          targets[i],
          embeddings,
          ProcessingOutcome.succeeded,
          capability: Capability.embeddings,
          version: service.model.version,
          latency: latency,
        );
        count++;
      }
    }
    return count;
  }

  @override
  Future<QueueBlock?> currentBlock() async {
    try {
      await _router.vision();
      return null;
    } on CapabilityUnavailableException catch (e) {
      return blockFor(e);
    }
  }

  /// Maps why vision is unavailable to what the queue screen shows.
  static QueueBlock blockFor(CapabilityUnavailableException e) {
    final name = e.providerName;
    if (name == null) return const NoVisionProvider();
    return switch (e.reason) {
      UnavailableReason.notConfigured => const NoVisionProvider(),
      UnavailableReason.blockedByLocalOnly => BlockedByLocalOnly(name),
      UnavailableReason.missingApiKey => ProviderConfigurationProblem(
        name,
        'Add an API key for $name',
      ),
      UnavailableReason.modelNotDownloaded => ProviderConfigurationProblem(
        name,
        'Download the on-device model for $name',
      ),
      UnavailableReason.unsupportedByProvider => ProviderConfigurationProblem(
        name,
        "$name can't understand images. Choose another vision provider.",
      ),
    };
  }
}
