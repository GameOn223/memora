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
}
