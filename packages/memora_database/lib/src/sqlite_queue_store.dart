import 'package:memora_core/memora_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'codec.dart';
import 'rows.dart';
import 'transactions.dart';

/// Rows a worker may claim at `?1` (now, in millis).
///
/// A `processing` row counts when its lease has run out, which is how work
/// held by a killed worker comes back.
const _claimable = '''
status IN ('captured', 'reprocessing', 'processing')
AND (lease_until IS NULL OR lease_until < ?1)
AND (next_attempt_at IS NULL OR next_attempt_at <= ?1)''';

/// The head of the waiting list, oldest taken first.
///
/// One query per status, each reading `memories (status, taken_at)` in order,
/// then a merge of the two short results. `status IN ('captured',
/// 'reprocessing')` with the same `ORDER BY` reads every waiting row and sorts
/// it in a temporary b-tree instead, which costs about 55 ms at 50,000
/// memories against 1 ms for this.
const _waitingSql = '''
SELECT * FROM (
  SELECT * FROM (
    SELECT * FROM memories WHERE status = 'captured'
    ORDER BY taken_at ASC, seq ASC LIMIT ?1
  )
  UNION ALL
  SELECT * FROM (
    SELECT * FROM memories WHERE status = 'reprocessing'
    ORDER BY taken_at ASC, seq ASC LIMIT ?1
  )
)
ORDER BY taken_at ASC, seq ASC LIMIT ?1''';

/// [QueueStore] on SQLite. See docs/architecture.md, section 5.2.
class SqliteQueueStore implements QueueStore {
  SqliteQueueStore(this._db);

  final Database _db;

  @override
  Future<Memory?> claimNext(DateTime now, Duration lease) async {
    return _db.transaction(() {
      final rows = _db.select(
        '''
UPDATE memories
SET status = 'processing',
    lease_until = ?2,
    attempts = attempts + 1,
    updated_at = ?1
WHERE id = (
  SELECT id FROM memories
  WHERE $_claimable
  ORDER BY taken_at ASC, seq ASC
  LIMIT 1
)
RETURNING *''',
        [toMillis(now), toMillis(now.add(lease))],
      );
      return rows.isEmpty ? null : memoryFromRow(rows.first);
    }, immediate: true);
  }

  /// Only affects a memory that is still processing. A worker whose lease ran
  /// out while another worker took the memory over reports into nothing.
  @override
  Future<void> markReady(String id, DateTime now) async {
    _db.execute(
      '''
UPDATE memories
SET status = 'ready', processed_at = ?1, updated_at = ?1, lease_until = NULL,
    next_attempt_at = NULL, failure_reason = NULL
WHERE id = ?2 AND status = 'processing' ''',
      [toMillis(now), id],
    );
  }

  /// Only affects a memory that is still processing.
  @override
  Future<void> releaseForRetry(
    String id, {
    required DateTime nextAttemptAt,
    required String reason,
    required DateTime now,
  }) async {
    _db.execute(
      '''
UPDATE memories
SET status = 'captured', lease_until = NULL, next_attempt_at = ?,
    failure_reason = ?, updated_at = ?
WHERE id = ? AND status = 'processing' ''',
      [toMillis(nextAttemptAt), reason, toMillis(now), id],
    );
  }

  /// Only affects a memory that is still processing, so a worker can't hand
  /// back an attempt another worker is using.
  @override
  Future<void> releaseWithoutAttempt(String id, DateTime now) async {
    _db.execute(
      '''
UPDATE memories
SET status = 'captured', lease_until = NULL, attempts = MAX(attempts - 1, 0),
    updated_at = ?
WHERE id = ? AND status = 'processing' ''',
      [toMillis(now), id],
    );
  }

  /// Only affects a memory that is still processing.
  @override
  Future<void> markFailed(String id, String reason, DateTime now) async {
    _db.execute(
      '''
UPDATE memories
SET status = 'failed', failure_reason = ?, lease_until = NULL,
    next_attempt_at = NULL, updated_at = ?
WHERE id = ? AND status = 'processing' ''',
      [reason, toMillis(now), id],
    );
  }

  /// Only affects failed memories.
  @override
  Future<void> retry(String id, DateTime now) async {
    _db.execute(
      '''
UPDATE memories
SET status = 'captured', attempts = 0, failure_reason = NULL,
    lease_until = NULL, next_attempt_at = NULL, updated_at = ?
WHERE id = ? AND status = 'failed' ''',
      [toMillis(now), id],
    );
  }

  /// Only affects ready and failed memories.
  @override
  Future<void> requestReprocess(String id, DateTime now) async {
    _db.execute(
      '''
UPDATE memories
SET status = 'reprocessing', attempts = 0, failure_reason = NULL,
    lease_until = NULL, next_attempt_at = NULL, updated_at = ?
WHERE id = ? AND status IN ('ready', 'failed')''',
      [toMillis(now), id],
    );
  }

  /// Processing items, then waiting items oldest taken first with their
  /// positions, then failed items, then up to [recentLimit] ready items with
  /// the most recently processed first.
  ///
  /// The waiting and failed lists are capped at [waitingLimit] each. A first
  /// import can leave tens of thousands of memories waiting, and the screen
  /// only shows the head of the queue. `MemoryStore.queueSummary` has the
  /// totals.
  @override
  Future<List<QueueItem>> queueItems({
    int waitingLimit = 200,
    int recentLimit = 20,
  }) async {
    // One read transaction for all four queries. A worker claiming a memory
    // halfway through would otherwise drop it from the answer, or show it
    // twice.
    return _db.transaction(() => _queueItems(waitingLimit, recentLimit));
  }

  List<QueueItem> _queueItems(int waitingLimit, int recentLimit) {
    List<Memory> select(String sql, [List<Object?> args = const []]) => [
      for (final row in _db.select(sql, args)) memoryFromRow(row),
    ];

    // Only a worker or two can hold memories at once, so this list is short
    // and always shown in full.
    final processing = select(
      "SELECT * FROM memories WHERE status = 'processing' "
      'ORDER BY taken_at ASC, seq ASC',
    );
    final waiting = select(_waitingSql, [waitingLimit]);
    final failed = select(
      "SELECT * FROM memories WHERE status = 'failed' "
      'ORDER BY taken_at ASC, seq ASC LIMIT ?',
      [waitingLimit],
    );
    final ready = select(
      "SELECT * FROM memories WHERE status = 'ready' "
      'ORDER BY processed_at DESC, seq DESC LIMIT ?',
      [recentLimit],
    );

    return [
      for (final memory in processing)
        QueueItem(memory: memory, position: null),
      for (final (index, memory) in waiting.indexed)
        QueueItem(memory: memory, position: index + 1),
      for (final memory in failed) QueueItem(memory: memory, position: null),
      for (final memory in ready) QueueItem(memory: memory, position: null),
    ];
  }

  @override
  Future<bool> hasWork(DateTime now) async {
    final row = _db.select(
      'SELECT EXISTS (SELECT 1 FROM memories WHERE $_claimable) AS work',
      [toMillis(now)],
    ).first;
    return row['work'] == 1;
  }
}
