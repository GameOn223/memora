import 'package:memora_core/memora_core.dart';

/// Loads and saves [QueuePolicy] under the `queue_policy` settings key.
///
/// Mirrors `QueuePolicyRepository` from `memora_core` (same key, same JSON),
/// so either can read what the other wrote.
abstract interface class QueuePolicySource {
  Future<QueuePolicy> load();

  Future<void> save(QueuePolicy policy);
}

class SettingsQueuePolicySource implements QueuePolicySource {
  const SettingsQueuePolicySource(this._settings);

  static const key = 'queue_policy';

  final SettingsStore _settings;

  @override
  Future<QueuePolicy> load() async {
    final raw = await _settings.read(key);
    if (raw is Map) {
      return QueuePolicy.fromJson(raw.cast<String, Object?>());
    }
    return const QueuePolicy();
  }

  @override
  Future<void> save(QueuePolicy policy) =>
      _settings.write(key, policy.toJson());
}
