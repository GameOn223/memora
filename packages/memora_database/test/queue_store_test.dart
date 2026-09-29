import 'package:memora_core/memora_core.dart';
import 'package:memora_database/memora_database.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  late MemoraDatabase db;
  late QueueStore queue;
  final now = DateTime.utc(2026, 9, 15, 2);
  const lease = Duration(minutes: 10);

  setUp(() {
    db = openTestDatabase();
    queue = db.queue;
  });

  Future<String> seed(
    DateTime takenAt, [
    ProcessingStatus status = ProcessingStatus.captured,
  ]) async {
    final id = await seedMemory(db, takenAt: takenAt);
    if (status != ProcessingStatus.captured) setStatus(db, id, status);
    return id;
  }

  Object? column(String id, String name) =>
      scalar(db, 'SELECT $name FROM memories WHERE id = ?', [id]);

  group('claimNext', () {
    test('claims the oldest captured or reprocessing memory', () async {
      await seed(DateTime.utc(2026, 6, 1), ProcessingStatus.ready);
      await seed(DateTime.utc(2026, 6, 2), ProcessingStatus.failed);
      await seed(DateTime.utc(2026, 8, 1));
      final reprocess = await seed(
        DateTime.utc(2026, 7, 15),
        ProcessingStatus.reprocessing,
      );

      final claimed = (await queue.claimNext(now, lease))!;
      expect(claimed.id, reprocess);
      expect(claimed.status, ProcessingStatus.processing);
      expect(claimed.attempts, 1);
      expect(claimed.updatedAt, now);
      expect(
        column(reprocess, 'lease_until'),
        now.add(lease).millisecondsSinceEpoch,
      );
    });

    test('breaks taken date ties by insertion order', () async {
      final taken = DateTime.utc(2026, 7, 1);
      final first = await seed(taken);
      await seed(taken);
      expect((await queue.claimNext(now, lease))!.id, first);
    });

    test('skips leased memories and memories backing off', () async {
      final leased = await seed(DateTime.utc(2026, 6, 1));
      setStatus(
        db,
        leased,
        ProcessingStatus.captured,
        leaseUntil: now.add(const Duration(minutes: 1)),
      );
      final backingOff = await seed(DateTime.utc(2026, 6, 2));
      setStatus(
        db,
        backingOff,
        ProcessingStatus.captured,
        nextAttemptAt: now.add(const Duration(minutes: 1)),
      );
      final due = await seed(DateTime.utc(2026, 6, 3));
      setStatus(db, due, ProcessingStatus.captured, nextAttemptAt: now);

      expect((await queue.claimNext(now, lease))!.id, due);
      expect(await queue.claimNext(now, lease), isNull);
    });

    test('recovers a processing memory whose lease expired', () async {
      final stuck = await seed(DateTime.utc(2026, 6, 1));
      setStatus(
        db,
        stuck,
        ProcessingStatus.processing,
        attempts: 1,
        leaseUntil: now.subtract(const Duration(seconds: 1)),
      );
      final busy = await seed(DateTime.utc(2026, 5, 1));
      setStatus(
        db,
        busy,
        ProcessingStatus.processing,
        attempts: 1,
        leaseUntil: now.add(const Duration(minutes: 5)),
      );

      final claimed = (await queue.claimNext(now, lease))!;
      expect(claimed.id, stuck);
      expect(claimed.attempts, 2);
      expect(await queue.claimNext(now, lease), isNull);
    });

    test('never hands out the same memory twice', () async {
      final a = await seed(DateTime.utc(2026, 6, 1));
      final b = await seed(DateTime.utc(2026, 6, 2));

      final first = await queue.claimNext(now, lease);
      final second = await queue.claimNext(now, lease);
      expect([first!.id, second!.id], [a, b]);
      expect(await queue.claimNext(now, lease), isNull);
    });

    test('two connections to one file claim different memories', () async {
      final path = tempDatabasePath();
      final ui = MemoraDatabase.open(path);
      addTearDown(ui.close);
      final worker = MemoraDatabase.open(path);
      addTearDown(worker.close);
      await ui.memories.insertCaptured([newMemory(), newMemory()], now);

      final fromWorker = await worker.queue.claimNext(now, lease);
      final fromUi = await ui.queue.claimNext(now, lease);
      expect(fromWorker, isNotNull);
      expect(fromUi, isNotNull);
      expect(fromUi!.id, isNot(fromWorker!.id));
      expect(await worker.queue.claimNext(now, lease), isNull);
    });

    test('returns null on an empty queue', () async {
      expect(await queue.claimNext(now, lease), isNull);
    });
  });

  group('finishing and releasing', () {
    late String id;
    final later = now.add(const Duration(minutes: 3));

    setUp(() async {
      id = await seed(DateTime.utc(2026, 7, 1));
      await queue.claimNext(now, lease);
    });

    test('markReady clears the lease and queue bookkeeping', () async {
      db.connection.execute(
        'UPDATE memories SET failure_reason = ?, next_attempt_at = ? '
        'WHERE id = ?',
        ['Timed out', now.millisecondsSinceEpoch, id],
      );
      await queue.markReady(id, later);

      final memory = (await db.memories.getMemory(id))!;
      expect(memory.status, ProcessingStatus.ready);
      expect(memory.processedAt, later);
      expect(memory.updatedAt, later);
      expect(memory.failureReason, isNull);
      expect(column(id, 'lease_until'), isNull);
      expect(column(id, 'next_attempt_at'), isNull);
    });

    test('releaseForRetry keeps the attempt and schedules the next', () async {
      final nextAttempt = now.add(const Duration(minutes: 5));
      await queue.releaseForRetry(
        id,
        nextAttemptAt: nextAttempt,
        reason: 'Rate limited',
        now: later,
      );

      final memory = (await db.memories.getMemory(id))!;
      expect(memory.status, ProcessingStatus.captured);
      expect(memory.attempts, 1);
      expect(memory.failureReason, 'Rate limited');
      expect(memory.updatedAt, later);
      expect(column(id, 'lease_until'), isNull);
      expect(column(id, 'next_attempt_at'), nextAttempt.millisecondsSinceEpoch);
      expect(await queue.claimNext(later, lease), isNull);
      expect((await queue.claimNext(nextAttempt, lease))!.id, id);
    });

    test('releaseWithoutAttempt gives the attempt back', () async {
      await queue.releaseWithoutAttempt(id, later);

      final memory = (await db.memories.getMemory(id))!;
      expect(memory.status, ProcessingStatus.captured);
      expect(memory.attempts, 0);
      expect(memory.updatedAt, later);
      expect(column(id, 'lease_until'), isNull);

      await queue.releaseWithoutAttempt(id, later);
      expect((await db.memories.getMemory(id))!.attempts, 0);
      expect((await queue.claimNext(later, lease))!.id, id);
    });

    test('markFailed records the reason', () async {
      await queue.markFailed(id, 'The provider refused the image', later);

      final memory = (await db.memories.getMemory(id))!;
      expect(memory.status, ProcessingStatus.failed);
      expect(memory.failureReason, 'The provider refused the image');
      expect(memory.updatedAt, later);
      expect(column(id, 'lease_until'), isNull);
      expect(await queue.claimNext(later, lease), isNull);
    });
  });

  group('a worker that lost its lease', () {
    late String id;
    final takeover = now.add(const Duration(minutes: 30));
    final tooLate = now.add(const Duration(minutes: 45));

    setUp(() async {
      id = await seed(DateTime.utc(2026, 7, 1));
      await queue.claimNext(now, lease);
      // The lease runs out, a second worker claims the same memory and
      // finishes it. The first worker is still alive and reports back.
      await queue.claimNext(takeover, lease);
      await queue.markReady(id, takeover);
    });

    test('cannot mark a finished memory ready again', () async {
      await queue.markReady(id, tooLate);

      final memory = (await db.memories.getMemory(id))!;
      expect(memory.status, ProcessingStatus.ready);
      expect(memory.processedAt, takeover);
      expect(memory.updatedAt, takeover);
    });

    test('cannot fail a finished memory', () async {
      await queue.markFailed(id, 'Timed out', tooLate);

      final memory = (await db.memories.getMemory(id))!;
      expect(memory.status, ProcessingStatus.ready);
      expect(memory.failureReason, isNull);
      expect(memory.updatedAt, takeover);
    });

    test('cannot put a finished memory back in the queue', () async {
      await queue.releaseForRetry(
        id,
        nextAttemptAt: tooLate.add(const Duration(minutes: 5)),
        reason: 'Rate limited',
        now: tooLate,
      );

      final memory = (await db.memories.getMemory(id))!;
      expect(memory.status, ProcessingStatus.ready);
      expect(memory.failureReason, isNull);
      expect(column(id, 'next_attempt_at'), isNull);
    });

    test('cannot give back an attempt it never used', () async {
      final before = (await db.memories.getMemory(id))!.attempts;
      expect(before, 2);

      await queue.releaseWithoutAttempt(id, tooLate);

      final memory = (await db.memories.getMemory(id))!;
      expect(memory.status, ProcessingStatus.ready);
      expect(memory.attempts, before);
    });

    test('cannot touch a memory that is waiting again', () async {
      setStatus(db, id, ProcessingStatus.captured, attempts: 0);

      await queue.markFailed(id, 'Timed out', tooLate);
      await queue.markReady(id, tooLate);

      expect(
        (await db.memories.getMemory(id))!.status,
        ProcessingStatus.captured,
      );
    });
  });

  group('user actions', () {
    test('retry moves a failed memory back to the queue', () async {
      final id = await seed(DateTime.utc(2026, 7, 1));
      setStatus(db, id, ProcessingStatus.failed, attempts: 3);
      db.connection.execute(
        'UPDATE memories SET failure_reason = ? WHERE id = ?',
        ['Timed out', id],
      );

      await queue.retry(id, now);

      final memory = (await db.memories.getMemory(id))!;
      expect(memory.status, ProcessingStatus.captured);
      expect(memory.attempts, 0);
      expect(memory.failureReason, isNull);
      expect(memory.updatedAt, now);
    });

    test('retry leaves a memory that is not failed alone', () async {
      final id = await seed(DateTime.utc(2026, 7, 1));
      setStatus(db, id, ProcessingStatus.ready, attempts: 1);

      await queue.retry(id, now);

      final memory = (await db.memories.getMemory(id))!;
      expect(memory.status, ProcessingStatus.ready);
      expect(memory.attempts, 1);
    });

    test('requestReprocess works for ready and failed memories', () async {
      final ready = await seed(DateTime.utc(2026, 7, 1));
      setStatus(db, ready, ProcessingStatus.ready, attempts: 1);
      final failed = await seed(DateTime.utc(2026, 7, 2));
      setStatus(db, failed, ProcessingStatus.failed, attempts: 3);
      final waiting = await seed(DateTime.utc(2026, 7, 3));

      for (final id in [ready, failed, waiting]) {
        await queue.requestReprocess(id, now);
      }

      for (final id in [ready, failed]) {
        final memory = (await db.memories.getMemory(id))!;
        expect(memory.status, ProcessingStatus.reprocessing);
        expect(memory.attempts, 0);
        expect(memory.updatedAt, now);
      }
      expect(
        (await db.memories.getMemory(waiting))!.status,
        ProcessingStatus.captured,
      );
    });
  });

  group('queueItems', () {
    test('orders processing, waiting, failed, then recent ready', () async {
      final processing = await seed(DateTime.utc(2026, 8, 5));
      setStatus(
        db,
        processing,
        ProcessingStatus.processing,
        leaseUntil: now.add(lease),
      );
      final laterWaiting = await seed(DateTime.utc(2026, 9, 1));
      setStatus(
        db,
        laterWaiting,
        ProcessingStatus.captured,
        nextAttemptAt: now.add(const Duration(minutes: 30)),
      );
      final firstWaiting = await seed(DateTime.utc(2026, 7, 1));
      final reprocessing = await seed(
        DateTime.utc(2026, 7, 10),
        ProcessingStatus.reprocessing,
      );
      final failed = await seed(DateTime.utc(2026, 6, 1));
      setStatus(db, failed, ProcessingStatus.failed);
      final oldestReady = await seed(DateTime.utc(2026, 5, 1));
      setStatus(
        db,
        oldestReady,
        ProcessingStatus.ready,
        processedAt: now.subtract(const Duration(hours: 3)),
      );
      final newestReady = await seed(DateTime.utc(2026, 5, 2));
      setStatus(
        db,
        newestReady,
        ProcessingStatus.ready,
        processedAt: now.subtract(const Duration(hours: 1)),
      );
      final middleReady = await seed(DateTime.utc(2026, 5, 3));
      setStatus(
        db,
        middleReady,
        ProcessingStatus.ready,
        processedAt: now.subtract(const Duration(hours: 2)),
      );

      final items = await queue.queueItems(recentLimit: 2);
      expect(items.map((i) => i.memory.id), [
        processing,
        firstWaiting,
        reprocessing,
        laterWaiting,
        failed,
        newestReady,
        middleReady,
      ]);
      expect(items.map((i) => i.position), [null, 1, 2, 3, null, null, null]);
    });

    test('is empty for an empty database', () async {
      expect(await queue.queueItems(), isEmpty);
    });

    test('caps the waiting and failed lists', () async {
      final waiting = <String>[];
      for (var day = 1; day <= 5; day++) {
        waiting.add(await seed(DateTime.utc(2026, 7, day)));
      }
      final failed = <String>[];
      for (var day = 1; day <= 3; day++) {
        final id = await seed(DateTime.utc(2026, 6, day));
        setStatus(db, id, ProcessingStatus.failed);
        failed.add(id);
      }

      final items = await queue.queueItems(waitingLimit: 2);
      expect(items.map((i) => i.memory.id), [
        waiting[0],
        waiting[1],
        failed[0],
        failed[1],
      ]);
      expect(items.map((i) => i.position), [1, 2, null, null]);

      expect(await queue.queueItems(waitingLimit: 0), isEmpty);
      expect((await queue.queueItems()).length, 8);

      // An item a worker holds is always shown, however tight the cap.
      final active = await seed(DateTime.utc(2026, 8, 1));
      setStatus(
        db,
        active,
        ProcessingStatus.processing,
        leaseUntil: now.add(lease),
      );
      expect(
        (await queue.queueItems(waitingLimit: 0)).single.memory.id,
        active,
      );
    });
  });

  group('hasWork', () {
    test('is true only when something can be claimed now', () async {
      expect(await queue.hasWork(now), isFalse);

      final id = await seed(DateTime.utc(2026, 7, 1));
      setStatus(
        db,
        id,
        ProcessingStatus.captured,
        nextAttemptAt: now.add(const Duration(minutes: 5)),
      );
      expect(await queue.hasWork(now), isFalse);
      expect(await queue.hasWork(now.add(const Duration(minutes: 5))), isTrue);

      setStatus(db, id, ProcessingStatus.ready);
      expect(await queue.hasWork(now), isFalse);

      setStatus(
        db,
        id,
        ProcessingStatus.processing,
        leaseUntil: now.add(lease),
      );
      expect(await queue.hasWork(now), isFalse);
      expect(await queue.hasWork(now.add(lease * 2)), isTrue);
    });
  });
}
