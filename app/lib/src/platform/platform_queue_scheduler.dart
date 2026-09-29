import 'package:memora_core/memora_core.dart';

import '../services/app_services.dart';
import 'messages.g.dart';
import 'queue_policy_store.dart';

/// [QueueScheduler] that hands the queue policy to WorkManager through
/// [SchedulerHostApi].
class PlatformQueueScheduler implements QueueScheduler {
  PlatformQueueScheduler({
    required this._policies,
    required this._queue,
    required this._router,
    this._clock = const SystemClock(),
    SchedulerHostApi? host,
  }) : _host = host ?? SchedulerHostApi();

  /// How far ahead to look for work. Items waiting out a retry backoff (up to
  /// 30 minutes) or a stale lease (10 minutes) still count as work, so the
  /// native job isn't cancelled while they wait.
  static const lookahead = Duration(minutes: 31);

  final QueuePolicySource _policies;
  final QueueStore _queue;
  final CapabilityRouter _router;
  final Clock _clock;
  final SchedulerHostApi _host;

  @override
  Future<QueuePolicy> policy() => _policies.load();

  @override
  Future<void> setPolicy(QueuePolicy policy) async {
    await _policies.save(policy);
    await _apply(policy);
  }

  @override
  Future<void> processNow() async {
    await _host.processNow(await _usesNetwork());
  }

  @override
  Future<void> refresh() async => _apply(await _policies.load());

  Future<void> _apply(QueuePolicy policy) async {
    final hasWork = await _queue.hasWork(_clock.now().add(lookahead));
    await _host.apply(
      schedulePolicyFrom(
        policy,
        usesNetwork: await _usesNetwork(),
        hasWork: hasWork,
      ),
    );
  }

  Future<bool> _usesNetwork() async =>
      (await _router.offDeviceProviders()).isNotEmpty;
}

SchedulePolicy schedulePolicyFrom(
  QueuePolicy policy, {
  required bool usesNetwork,
  required bool hasWork,
}) => SchedulePolicy(
  immediate: policy.mode == QueueMode.immediate,
  paused: policy.paused,
  windowStartMinutes: policy.windowStartMinutes,
  windowEndMinutes: policy.windowEndMinutes,
  requiresUnmeteredNetwork: usesNetwork,
  hasWork: hasWork,
);
