import '../model/processing.dart';
import '../ports/stores.dart';

/// Loads and saves the [QueuePolicy] through the generic settings store.
class QueuePolicyRepository {
  const QueuePolicyRepository(this._store);

  static const key = 'queue_policy';

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
}
