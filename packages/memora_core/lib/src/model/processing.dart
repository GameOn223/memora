import 'package:meta/meta.dart';

/// The four things an AI provider can do for Memora.
enum Capability {
  vision('vision'),
  chat('chat'),
  embeddings('embeddings'),
  reranking('reranking');

  const Capability(this.key);

  final String key;

  static Capability fromKey(String key) => Capability.values.firstWhere(
    (c) => c.key == key,
    orElse: () => throw ArgumentError.value(key, 'key', 'Unknown capability'),
  );
}

/// Outcome of one capability run for one memory.
enum ProcessingOutcome {
  succeeded('succeeded'),
  failed('failed');

  const ProcessingOutcome(this.dbValue);

  final String dbValue;

  static ProcessingOutcome fromDb(String value) =>
      value == 'succeeded' ? succeeded : failed;
}

/// A row in `processing_metadata`: which provider and model did what, and how
/// it went. Shown at the bottom of the detail screen.
@immutable
class ProcessingRecord {
  const ProcessingRecord({
    required this.memoryId,
    required this.capability,
    required this.provider,
    required this.model,
    required this.outcome,
    required this.createdAt,
    this.version,
    this.latency,
    this.error,
  });

  final String memoryId;
  final Capability capability;
  final String provider;
  final String model;
  final String? version;
  final ProcessingOutcome outcome;
  final Duration? latency;
  final String? error;
  final DateTime createdAt;
}

/// When the queue runs.
enum QueueMode {
  /// Between the window start and end while charging. The default.
  overnight('overnight'),

  /// As soon as images are added.
  immediate('immediate');

  const QueueMode(this.key);

  final String key;

  static QueueMode fromKey(String key) =>
      key == 'immediate' ? immediate : overnight;
}

/// User-controlled queue behavior, passed to the native scheduler.
@immutable
class QueuePolicy {
  const QueuePolicy({
    this.mode = QueueMode.overnight,
    this.paused = false,
    this.windowStartMinutes = 60,
    this.windowEndMinutes = 420,
  });

  factory QueuePolicy.fromJson(Map<String, Object?> json) => QueuePolicy(
    mode: QueueMode.fromKey(json['mode'] as String? ?? 'overnight'),
    paused: json['paused'] as bool? ?? false,
    windowStartMinutes: json['window_start_minutes'] as int? ?? 60,
    windowEndMinutes: json['window_end_minutes'] as int? ?? 420,
  );

  final QueueMode mode;
  final bool paused;

  /// Minutes after local midnight. 60 is 01:00.
  final int windowStartMinutes;

  /// Minutes after local midnight. 420 is 07:00.
  final int windowEndMinutes;

  /// Whether [localTime] falls inside the overnight window. Handles windows
  /// that cross midnight, such as 23:00 to 06:00.
  bool isInsideWindow(DateTime localTime) {
    final minutes = localTime.hour * 60 + localTime.minute;
    if (windowStartMinutes <= windowEndMinutes) {
      return minutes >= windowStartMinutes && minutes < windowEndMinutes;
    }
    return minutes >= windowStartMinutes || minutes < windowEndMinutes;
  }

  /// Whether the queue may process an item right now.
  bool allowsProcessingAt(DateTime localTime, {bool processNow = false}) {
    if (paused) return false;
    if (processNow || mode == QueueMode.immediate) return true;
    return isInsideWindow(localTime);
  }

  /// The next local time the window opens, strictly after [from] unless
  /// [from] is already inside the window.
  DateTime nextWindowStart(DateTime from) {
    if (isInsideWindow(from)) return from;
    final today = DateTime(
      from.year,
      from.month,
      from.day,
      windowStartMinutes ~/ 60,
      windowStartMinutes % 60,
    );
    return today.isAfter(from) ? today : today.add(const Duration(days: 1));
  }

  QueuePolicy copyWith({QueueMode? mode, bool? paused}) => QueuePolicy(
    mode: mode ?? this.mode,
    paused: paused ?? this.paused,
    windowStartMinutes: windowStartMinutes,
    windowEndMinutes: windowEndMinutes,
  );

  Map<String, Object?> toJson() => {
    'mode': mode.key,
    'paused': paused,
    'window_start_minutes': windowStartMinutes,
    'window_end_minutes': windowEndMinutes,
  };

  @override
  bool operator ==(Object other) =>
      other is QueuePolicy &&
      other.mode == mode &&
      other.paused == paused &&
      other.windowStartMinutes == windowStartMinutes &&
      other.windowEndMinutes == windowEndMinutes;

  @override
  int get hashCode =>
      Object.hash(mode, paused, windowStartMinutes, windowEndMinutes);
}

/// Totals for the queue screen header.
@immutable
class QueueSummary {
  const QueueSummary({
    required this.total,
    required this.ready,
    required this.waiting,
    required this.processing,
    required this.failed,
  });

  final int total;
  final int ready;

  /// Captured or waiting to be reprocessed.
  final int waiting;
  final int processing;
  final int failed;

  static const empty = QueueSummary(
    total: 0,
    ready: 0,
    waiting: 0,
    processing: 0,
    failed: 0,
  );
}

/// Why the queue can't make progress, shown on the queue screen.
sealed class QueueBlock {
  const QueueBlock();
}

/// No vision provider is selected.
final class NoVisionProvider extends QueueBlock {
  const NoVisionProvider();
}

/// The selected vision provider is refused by local-only mode.
final class BlockedByLocalOnly extends QueueBlock {
  const BlockedByLocalOnly(this.providerName);

  final String providerName;
}

/// The provider rejected the configuration, for example a bad API key.
final class ProviderConfigurationProblem extends QueueBlock {
  const ProviderConfigurationProblem(this.providerName, this.message);

  final String providerName;
  final String message;
}

/// The provider is rate limiting Memora. Nothing is wrong with the settings
/// or the images, so the queue waits and picks up again by itself.
final class RateLimited extends QueueBlock {
  const RateLimited(this.providerName, this.retryAt);

  final String providerName;

  /// When the queue will try the provider again.
  final DateTime retryAt;
}

/// A provider is selected but has nothing that can run the capability with
/// the chosen model, either because the provider cannot do it at all or
/// because that model id is gone from it.
final class ProviderUnavailable extends QueueBlock {
  const ProviderUnavailable(this.providerName, this.modelId);

  final String providerName;

  /// The model the user picked, when there is one.
  final String? modelId;
}

/// A rate limit the queue is waiting out.
///
/// Saved through the settings store rather than held in memory: the
/// background worker is what meets the rate limit and the UI isolate is what
/// asks about it.
@immutable
class QueueRateLimit {
  const QueueRateLimit({required this.providerName, required this.retryAt});

  factory QueueRateLimit.fromJson(Map<String, Object?> json) => QueueRateLimit(
    providerName: json['provider_name'] as String? ?? '',
    retryAt: DateTime.fromMillisecondsSinceEpoch(
      json['retry_at'] as int? ?? 0,
      isUtc: true,
    ),
  );

  final String providerName;

  /// When the queue will try the provider again.
  final DateTime retryAt;

  /// Whether the wait is still on at [now].
  bool holdsAt(DateTime now) => retryAt.isAfter(now);

  /// The same thing as a [QueueBlock], for the queue screen.
  RateLimited get block => RateLimited(providerName, retryAt);

  Map<String, Object?> toJson() => {
    'provider_name': providerName,
    'retry_at': retryAt.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is QueueRateLimit &&
      other.providerName == providerName &&
      other.retryAt.isAtSameMomentAs(retryAt);

  @override
  int get hashCode => Object.hash(providerName, retryAt.millisecondsSinceEpoch);
}
