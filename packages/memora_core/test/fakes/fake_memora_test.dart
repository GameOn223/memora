import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

import 'fake_stores.dart';

/// Checks that the fakes behave like the port docs say, so service tests
/// built on them mean something.
void main() {
  final now = DateTime(2026, 9, 15, 2);
  late FakeMemora db;

  setUp(() => db = FakeMemora());

  group('queue', () {
    test('claims oldest taken first and respects leases and backoff', () async {
      db
        ..seed(
          id: 'new',
          status: ProcessingStatus.captured,
          takenAt: DateTime(2026, 9, 2),
        )
        ..seed(
          id: 'old',
          status: ProcessingStatus.reprocessing,
          takenAt: DateTime(2026, 9, 1),
        );

      final first = await db.claimNext(now, const Duration(minutes: 10));
      expect(first!.id, 'old');
      expect(first.status, ProcessingStatus.processing);
      expect(first.attempts, 1);

      await db.releaseForRetry(
        'old',
        nextAttemptAt: now.add(const Duration(minutes: 5)),
        reason: 'timeout',
        now: now,
      );
      expect((await db.claimNext(now, const Duration(minutes: 10)))!.id, 'new');
      expect(await db.claimNext(now, const Duration(minutes: 10)), isNull);
      expect(await db.hasWork(now), isFalse);

      final later = now.add(const Duration(minutes: 11));
      expect(await db.hasWork(later), isTrue);
      expect(
        (await db.claimNext(later, const Duration(minutes: 10)))!.id,
        'old',
        reason: 'backoff elapsed',
      );
      expect(
        (await db.claimNext(later, const Duration(minutes: 10)))!.id,
        'new',
        reason: 'its lease expired',
      );
    });
  });

  group('search', () {
    setUp(() {
      db
        ..seed(
          id: 'aug',
          category: 'utility_bill',
          summary: 'Reliance electricity bill',
          takenAt: DateTime(2026, 8, 5),
          entities: [entity('Reliance')],
          attributes: [amount(2103), dateAttribute('due_date', '2026-08-31')],
        )
        ..seed(
          id: 'mac',
          category: 'comparison',
          summary: 'MacBook price comparison',
          takenAt: DateTime(2026, 8, 20),
          attributes: [amount(124900)],
        );
    });

    test('structured filters combine', () async {
      expect(
        await db.structured(
          const RetrievalQuery(
            attributes: [AttributeFilter(type: 'amount', min: 2000)],
          ),
        ),
        ['mac', 'aug'],
      );
      expect(
        await db.structured(
          const RetrievalQuery(
            entities: [EntityFilter(value: 'reliance')],
            attributes: [AttributeFilter(type: 'amount', max: 5000)],
          ),
        ),
        ['aug'],
      );
    });

    test('full text finds prefixes and cards carry facts', () async {
      final hits = await db.fullText('electric');
      expect(hits.single.id, 'aug');
      final card = (await db.cards(['aug'])).single;
      expect(card.facts, {'amount': '₹2,103', 'due_date': '31 Aug 2026'});
    });
  });
}
