import 'package:memora_core/memora_core.dart';

import 'fake_memora_state.dart';

/// In-memory [QueueStore] with the same claim rules as the SQL version.
mixin FakeQueueStore on FakeMemoraState implements QueueStore {
  bool _claimable(MemoryRow r, DateTime now) {
    final lease = r.leaseUntil;
    final next = r.nextAttemptAt;
    final waiting =
        (r.status == ProcessingStatus.captured ||
            r.status == ProcessingStatus.reprocessing) &&
        (lease == null || lease.isBefore(now)) &&
        (next == null || !next.isAfter(now));
    final expired =
        r.status == ProcessingStatus.processing &&
        lease != null &&
        lease.isBefore(now);
    return waiting || expired;
  }

  int _oldestTaken(MemoryRow a, MemoryRow b) {
    final byTaken = a.takenAt.compareTo(b.takenAt);
    return byTaken != 0 ? byTaken : a.seq.compareTo(b.seq);
  }

  @override
  Future<Memory?> claimNext(DateTime now, Duration lease) async {
    final candidates = rows.values.where((r) => _claimable(r, now)).toList()
      ..sort(_oldestTaken);
    if (candidates.isEmpty) return null;
    final row = candidates.first
      ..status = ProcessingStatus.processing
      ..leaseUntil = now.add(lease)
      ..attempts += 1
      ..updatedAt = now;
    touch();
    return row.toMemory();
  }

  @override
  Future<void> markReady(String id, DateTime now) async {
    rows[id]
      ?..status = ProcessingStatus.ready
      ..processedAt = now
      ..leaseUntil = null
      ..failureReason = null
      ..nextAttemptAt = null
      ..updatedAt = now;
    touch();
  }

  @override
  Future<void> releaseForRetry(
    String id, {
    required DateTime nextAttemptAt,
    required String reason,
    required DateTime now,
  }) async {
    rows[id]
      ?..status = ProcessingStatus.captured
      ..leaseUntil = null
      ..nextAttemptAt = nextAttemptAt
      ..failureReason = reason
      ..updatedAt = now;
    touch();
  }

  @override
  Future<void> releaseWithoutAttempt(
    String id,
    DateTime now, {
    DateTime? nextAttemptAt,
    String? reason,
  }) async {
    final row = rows[id];
    if (row == null || row.status != ProcessingStatus.processing) return;
    row
      ..status = ProcessingStatus.captured
      ..leaseUntil = null
      ..attempts = row.attempts > 0 ? row.attempts - 1 : 0
      ..nextAttemptAt = nextAttemptAt
      ..failureReason = reason ?? row.failureReason
      ..updatedAt = now;
    touch();
  }

  @override
  Future<void> markFailed(String id, String reason, DateTime now) async {
    rows[id]
      ?..status = ProcessingStatus.failed
      ..failureReason = reason
      ..leaseUntil = null
      ..nextAttemptAt = null
      ..updatedAt = now;
    touch();
  }

  @override
  Future<void> retry(String id, DateTime now) async {
    final row = rows[id];
    if (row == null || row.status != ProcessingStatus.failed) return;
    row
      ..status = ProcessingStatus.captured
      ..attempts = 0
      ..failureReason = null
      ..nextAttemptAt = null
      ..updatedAt = now;
    touch();
  }

  @override
  Future<void> requestReprocess(String id, DateTime now) async {
    final row = rows[id];
    if (row == null ||
        (row.status != ProcessingStatus.ready &&
            row.status != ProcessingStatus.failed)) {
      return;
    }
    row
      ..status = ProcessingStatus.reprocessing
      ..attempts = 0
      ..failureReason = null
      ..nextAttemptAt = null
      ..updatedAt = now;
    touch();
  }

  @override
  Future<List<QueueItem>> queueItems({
    int recentLimit = 20,
    int waitingLimit = 200,
  }) async {
    List<MemoryRow> withStatus(Set<ProcessingStatus> statuses) =>
        rows.values.where((r) => statuses.contains(r.status)).toList()
          ..sort(_oldestTaken);
    final processing = withStatus({ProcessingStatus.processing});
    final waiting = withStatus({
      ProcessingStatus.captured,
      ProcessingStatus.reprocessing,
    });
    final failed = withStatus({ProcessingStatus.failed});
    final ready = withStatus({ProcessingStatus.ready})
      ..sort(
        (a, b) => (b.processedAt ?? b.updatedAt).compareTo(
          a.processedAt ?? a.updatedAt,
        ),
      );
    return [
      for (final r in processing)
        QueueItem(memory: r.toMemory(), position: null),
      for (var i = 0; i < waiting.length && i < waitingLimit; i++)
        QueueItem(memory: waiting[i].toMemory(), position: i + 1),
      for (final r in failed.take(waitingLimit))
        QueueItem(memory: r.toMemory(), position: null),
      for (final r in ready.take(recentLimit))
        QueueItem(memory: r.toMemory(), position: null),
    ];
  }

  @override
  Future<bool> hasWork(DateTime now) async =>
      rows.values.any((r) => _claimable(r, now));
}
