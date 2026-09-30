import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:memora_core/memora_core.dart';

import 'data_version.dart';
import 'services.dart';

/// Everything the queue screen shows.
@immutable
class QueueView {
  const QueueView({
    required this.summary,
    required this.items,
    required this.policy,
    this.block,
  });

  final QueueSummary summary;
  final List<QueueItem> items;
  final QueuePolicy policy;

  /// Why nothing is being processed, if anything is wrong.
  final QueueBlock? block;

  /// Images waiting for understanding, including the one in progress.
  int get waiting => summary.waiting + summary.processing;
}

/// How many recently finished items the queue screen lists after the
/// pending ones.
const queueRecentLimit = 3;

final queueViewProvider = FutureProvider<QueueView>((ref) async {
  ref.watch(dataVersionProvider);
  final services = ref.watch(appServicesProvider);
  return QueueView(
    summary: await services.memories.queueSummary(),
    items: await services.queue.queueItems(recentLimit: queueRecentLimit),
    policy: await services.scheduler.policy(),
    block: await services.pipeline.currentBlock(),
  );
});

final queueSummaryProvider = FutureProvider<QueueSummary>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.watch(appServicesProvider).memories.queueSummary();
});

/// The badge on the home header: everything not understood yet.
final queueWaitingCountProvider = Provider<int>((ref) {
  final summary = ref.watch(queueSummaryProvider).value;
  if (summary == null) return 0;
  return summary.waiting + summary.processing + summary.failed;
});

final queuePolicyProvider =
    AsyncNotifierProvider<QueuePolicyController, QueuePolicy>(
      QueuePolicyController.new,
    );

class QueuePolicyController extends AsyncNotifier<QueuePolicy> {
  @override
  Future<QueuePolicy> build() {
    ref.watch(dataVersionProvider);
    return ref.watch(appServicesProvider).scheduler.policy();
  }

  Future<void> setMode(QueueMode mode) async {
    final current = state.value ?? const QueuePolicy();
    await _save(current.copyWith(mode: mode));
  }

  Future<void> setPaused({required bool paused}) async {
    final current = state.value ?? const QueuePolicy();
    await _save(current.copyWith(paused: paused));
  }

  Future<void> _save(QueuePolicy policy) async {
    state = AsyncData(policy);
    await ref.read(appServicesProvider).scheduler.setPolicy(policy);
    await ref.read(dataVersionProvider.notifier).check();
  }
}
