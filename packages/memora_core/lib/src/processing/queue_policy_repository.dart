import '../model/processing.dart';
import '../ports/stores.dart';

/// The queue's settings-backed state: the [QueuePolicy] the user chose and
/// the rate limit the queue is waiting out.
///
/// Both go through the generic settings store so every isolate reads the same
/// answer. The background worker is what meets a rate limit, and the UI
/// isolate is what asks why nothing is being processed.
class QueuePolicyRepository {
  const QueuePolicyRepository(this._store);

  static const key = 'queue_policy';

  /// Settings key holding the rate limit note. Machine state rather than a
  /// choice the user made, so it stays out of [key].
  static const rateLimitKey = 'queue_rate_limit';

  final SettingsStore _store;

  /// The saved policy, or the default when nothing readable is stored.
  Future<QueuePolicy> load() async {
    final raw = await _store.read(key);
    if (raw is! Map) return const QueuePolicy();
    try {
      return QueuePolicy.fromJson(raw.cast<String, Object?>());
    } on TypeError {
      // Written by a broken build or edited by hand. Start over.
      return const QueuePolicy();
    }
  }

  Future<void> save(QueuePolicy policy) => _store.write(key, policy.toJson());

  /// The rate limit still in force at [now], or null when there is none.
  ///
  /// A note whose time has passed counts as gone, so nothing has to tidy up
  /// before the queue can run again.
  Future<QueueRateLimit?> loadRateLimit(DateTime now) async {
    final raw = await _store.read(rateLimitKey);
    if (raw is! Map) return null;
    try {
      final limit = QueueRateLimit.fromJson(raw.cast<String, Object?>());
      return limit.holdsAt(now) ? limit : null;
    } on TypeError {
      return null;
    }
  }

  Future<void> saveRateLimit(QueueRateLimit limit) =>
      _store.write(rateLimitKey, limit.toJson());

  /// Forgets any rate limit note. Reads first, so the common case of a queue
  /// that was never rate limited costs a lookup rather than a write.
  Future<void> clearRateLimit() async {
    if (await _store.read(rateLimitKey) == null) return;
    await _store.write(rateLimitKey, null);
  }
}
