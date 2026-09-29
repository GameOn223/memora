import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/platform/messages.g.dart';
import 'package:memora/src/platform/platform_queue_scheduler.dart';
import 'package:memora/src/platform/queue_policy_store.dart';
import 'package:memora_core/memora_core.dart';

import 'fakes.dart';

void main() {
  test('sends the policy with network and work state', () async {
    final host = _FakeSchedulerHost();
    final settings = MemorySettings();
    final registry = ProviderRegistry()
      ..register(
        const ProviderDescriptor(
          id: 'cloudy',
          displayName: 'Cloudy',
          location: ProviderLocation.cloud,
          capabilities: {Capability.vision},
        ),
        (_) => throw UnimplementedError(),
      );
    await AiSettingsRepository(settings).save(
      const AiSettings(
        selections: {Capability.vision: CapabilitySelection('cloudy', 'model')},
      ),
    );
    final queue = _FakeQueueStore();
    final now = DateTime(2026, 9, 15, 12);
    final scheduler = PlatformQueueScheduler(
      policies: SettingsQueuePolicySource(settings),
      queue: queue,
      router: CapabilityRouter(
        registry: registry,
        settings: AiSettingsRepository(settings),
        secrets: NoSecrets(),
      ),
      clock: FixedClock(now),
      host: host,
    );

    await scheduler.setPolicy(
      const QueuePolicy(mode: QueueMode.immediate, paused: true),
    );

    expect(
      await scheduler.policy(),
      const QueuePolicy(mode: QueueMode.immediate, paused: true),
    );
    final sent = host.applied.single;
    expect(sent.immediate, isTrue);
    expect(sent.paused, isTrue);
    expect(sent.windowStartMinutes, 60);
    expect(sent.windowEndMinutes, 420);
    expect(sent.requiresUnmeteredNetwork, isTrue);
    expect(sent.hasWork, isTrue);
    expect(queue.askedAt, now.add(PlatformQueueScheduler.lookahead));

    await scheduler.processNow();
    expect(host.processNowCalls, [true]);

    await scheduler.refresh();
    expect(host.applied, hasLength(2));
  });

  test('policy JSON matches the core settings format', () async {
    final settings = MemorySettings();
    final source = SettingsQueuePolicySource(settings);

    expect(await source.load(), const QueuePolicy());
    await source.save(const QueuePolicy(mode: QueueMode.immediate));

    expect(await settings.read('queue_policy'), {
      'mode': 'immediate',
      'paused': false,
      'window_start_minutes': 60,
      'window_end_minutes': 420,
    });
  });

  test('maps an overnight policy without network providers', () {
    final policy = schedulePolicyFrom(
      const QueuePolicy(windowStartMinutes: 1380, windowEndMinutes: 360),
      usesNetwork: false,
      hasWork: false,
    );
    expect(policy.immediate, isFalse);
    expect(policy.paused, isFalse);
    expect(policy.windowStartMinutes, 1380);
    expect(policy.windowEndMinutes, 360);
    expect(policy.requiresUnmeteredNetwork, isFalse);
    expect(policy.hasWork, isFalse);
  });
}

class _FakeSchedulerHost extends SchedulerHostApi {
  final applied = <SchedulePolicy>[];
  final processNowCalls = <bool>[];

  @override
  Future<void> apply(SchedulePolicy policy) async => applied.add(policy);

  @override
  Future<void> processNow(bool requiresUnmeteredNetwork) async =>
      processNowCalls.add(requiresUnmeteredNetwork);
}

class _FakeQueueStore implements QueueStore {
  DateTime? askedAt;

  @override
  Future<bool> hasWork(DateTime now) async {
    askedAt = now;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
