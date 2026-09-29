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

  /// Attempts before a transient error fails a memory for good. Four, so
  /// the whole 1, 5 and 30 minute ladder gets used.
  static const maxAttempts = 4;

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

  /// The soonest retry the current [runQueue] scheduled, reported so the
  /// scheduler can wait rather than starting again immediately.
  DateTime? _earliestRetry;

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
    } on Object catch (e) {
      final outcome = await _fail(memory, 'The image file could not be read.');
      await _record(memory.id, vision, ProcessingOutcome.failed, error: '$e');
      return outcome;
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
      // The status write comes first in every arm below. A processing record
      // is bookkeeping, and losing one must never leave the row stuck in
      // `processing` until its lease expires.
      await _queue.releaseWithoutAttempt(memory.id, _clock.now());
      await _failureRecord(memory.id, vision, stopwatch, e.message);
      return QueueBlocked(
        ProviderConfigurationProblem(vision.provider.displayName, e.message),
      );
    } on AiContentException catch (e) {
      final outcome = await _fail(memory, e.message);
      await _failureRecord(memory.id, vision, stopwatch, e.message);
      return outcome;
    } on AiTransientException catch (e) {
      final outcome = await _retryOrFail(
        memory,
        e.message,
        retryAfter: e.retryAfter,
      );
      await _failureRecord(memory.id, vision, stopwatch, e.message);
      return outcome;
    } on FormatException catch (e) {
      // Structured output that could not be parsed is usually a one-off,
      // so it gets the same retry ladder as a timeout.
      final outcome = await _retryOrFail(
        memory,
        'The provider returned data Memora could not read.',
      );
      await _failureRecord(memory.id, vision, stopwatch, e.message);
      return outcome;
    } on Object catch (e) {
      // Anything unexpected is retried like a transient error, so a bug in
      // one adapter can't leave a memory stuck in processing.
      final outcome = await _retryOrFail(
        memory,
        'Something went wrong while understanding this image.',
      );
      await _failureRecord(memory.id, vision, stopwatch, '$e');
      return outcome;
    }
  }

  Future<void> _failureRecord(
    String memoryId,
    Resolved<Object> resolved,
    Stopwatch stopwatch,
    String error,
  ) => _record(
    memoryId,
    resolved,
    ProcessingOutcome.failed,
    latency: stopwatch.elapsed,
    error: error,
  );

  Future<ProcessOutcome> _retryOrFail(
    Memory memory,
    String reason, {
    Duration? retryAfter,
  }) async {
    if (memory.attempts >= maxAttempts) return _fail(memory, reason);
    final now = _clock.now();
    var wait = backoffFor(memory.attempts);
    if (retryAfter != null && retryAfter > wait) wait = retryAfter;
    final due = now.add(wait);
    if (_earliestRetry == null || due.isBefore(_earliestRetry!)) {
      _earliestRetry = due;
    }
    await _queue.releaseForRetry(
      memory.id,
      nextAttemptAt: due,
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

  /// Writes one provenance row. It never throws: the detail screen losing a
  /// line is a small loss next to a memory stuck in `processing` because the
  /// database was busy for a moment.
  Future<void> _record(
    String memoryId,
    Resolved<Object> resolved,
    ProcessingOutcome outcome, {
    Capability capability = Capability.vision,
    String? version,
    Duration? latency,
    String? error,
  }) async {
    try {
      await _memories.addProcessingRecord(
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
    } on Object {
      // Nothing to do about it here, and nothing depends on it.
    }
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
    _earliestRetry = null;

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

    // Anything captured or reprocessing still counts as work, including
    // memories waiting out a backoff. Otherwise the scheduler would hear
    // "nothing left" and never come back for the retry.
    final summary = await _memories.queueSummary();
    return QueueRunReport(
      processed: processed,
      remaining: summary.waiting > 0,
      block: block,
      nextAttemptAt: _earliestRetry,
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
    // A cloud model may only learn its dimensions from its first response.
    // Ask it something small first, so "which memories have no vector" is
    // asked about the model the vectors are actually tagged with.
    if (service.model.dimensions == 0) {
      try {
        await service.embed(const ['memora']);
      } on Object {
        return 0;
      }
    }
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
