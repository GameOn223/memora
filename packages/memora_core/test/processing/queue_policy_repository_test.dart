import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

import '../fakes/fake_stores.dart';

void main() {
  late InMemorySettingsStore settings;
  late QueuePolicyRepository repository;

  setUp(() {
    settings = InMemorySettingsStore();
    repository = QueuePolicyRepository(settings);
  });

  test('defaults when nothing is saved', () async {
    expect(await repository.load(), const QueuePolicy());
  });

  test('round-trips under the queue_policy key', () async {
    const policy = QueuePolicy(mode: QueueMode.immediate, paused: true);
    await repository.save(policy);

    expect(QueuePolicyRepository.key, 'queue_policy');
    expect(settings.values['queue_policy'], policy.toJson());
    expect(await repository.load(), policy);
  });

  test('falls back to defaults when the stored value is unreadable', () async {
    await settings.write('queue_policy', {'mode': 3, 'paused': 'yes'});
    expect(await repository.load(), const QueuePolicy());

    await settings.write('queue_policy', 'nonsense');
    expect(await repository.load(), const QueuePolicy());
  });

  group('rate limit note', () {
    const oneMinute = Duration(minutes: 1);
    final retryAt = DateTime.utc(2026, 9, 15, 2, 20);
    final limit = QueueRateLimit(providerName: 'NVIDIA', retryAt: retryAt);

    test('round-trips under its own key', () async {
      expect(QueuePolicyRepository.rateLimitKey, 'queue_rate_limit');
      await repository.saveRateLimit(limit);

      expect(
        await repository.loadRateLimit(retryAt.subtract(oneMinute)),
        limit,
      );
      expect(await repository.load(), const QueuePolicy());
    });

    test('is gone once its time has passed', () async {
      await repository.saveRateLimit(limit);

      expect(await repository.loadRateLimit(retryAt), isNull);
      expect(await repository.loadRateLimit(retryAt.add(oneMinute)), isNull);
    });

    test('clearing writes nothing when there is nothing to clear', () async {
      await repository.clearRateLimit();
      expect(settings.values, isEmpty);

      await repository.saveRateLimit(limit);
      await repository.clearRateLimit();
      expect(settings.values.containsKey('queue_rate_limit'), isFalse);
    });

    test('an unreadable note counts as no note', () async {
      await settings.write('queue_rate_limit', {'retry_at': 'soon'});
      expect(await repository.loadRateLimit(retryAt), isNull);

      await settings.write('queue_rate_limit', 'nonsense');
      expect(await repository.loadRateLimit(retryAt), isNull);
    });
  });
}
