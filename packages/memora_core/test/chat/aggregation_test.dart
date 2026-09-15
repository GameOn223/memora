import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

import '../fakes/fake_stores.dart';

void main() {
  late FakeMemora db;
  late Aggregator aggregator;

  setUp(() {
    db = FakeMemora()
      ..seed(
        id: 'a',
        takenAt: DateTime(2026, 7, 1),
        attributes: [
          amount(100, label: 'tax'),
          amount(1100),
          dateAttribute('due_date', '2026-07-20'),
        ],
      )
      ..seed(
        id: 'b',
        takenAt: DateTime(2026, 8, 1),
        attributes: [amount(900), dateAttribute('due_date', '2026-08-20')],
      )
      ..seed(
        id: 'c',
        takenAt: DateTime(2026, 9, 1),
        attributes: [amount(20, currency: 'USD')],
      )
      ..seed(id: 'd', takenAt: DateTime(2026, 9, 2));
    aggregator = Aggregator(db);
  });

  test('max reports the winner, currency and skipped values', () async {
    final outcome = await aggregator.run(
      ['a', 'b', 'c', 'd'],
      AggregateOp.max,
      attribute: 'amount',
    );

    expect(outcome.display, '₹1,100');
    expect(outcome.memoryId, 'a');
    expect(outcome.skipped, 1);
    expect(outcome.toToolJson(), {
      'op': 'max',
      'attribute': 'amount',
      'value': 1100,
      'display': '₹1,100',
      'currency': 'INR',
      'memory_id': 'a',
      'skipped_other_currency': 1,
    });
  });

  test('sum lists contributing memories', () async {
    final outcome = await aggregator.run(
      ['a', 'b'],
      AggregateOp.sum,
      attribute: 'amount',
    );
    expect(outcome.toToolJson(), {
      'op': 'sum',
      'attribute': 'amount',
      'value': 2000,
      'display': '₹2,000',
      'currency': 'INR',
      'memory_ids': ['a', 'b'],
    });
  });

  test('count with and without an attribute', () async {
    final all = await aggregator.run(['a', 'b', 'c', 'd'], AggregateOp.count);
    expect(all.toToolJson(), {'op': 'count', 'value': 4, 'display': '4'});

    final withDue = await aggregator.run(
      ['a', 'b', 'c', 'd'],
      AggregateOp.count,
      attribute: 'due_date',
    );
    expect(withDue.value, 2);
  });

  test('latest without an attribute is the newest memory', () async {
    final outcome = await aggregator.run(['a', 'd', 'b'], AggregateOp.latest);
    expect(outcome.memoryId, 'd');
    expect(outcome.display, '2 Sep 2026');
  });

  test('dates support max and min but not sums', () async {
    final latestDue = await aggregator.run(
      ['a', 'b'],
      AggregateOp.max,
      attribute: 'due_date',
    );
    expect(latestDue.display, '20 Aug 2026');
    expect(latestDue.memoryId, 'b');

    final sum = await aggregator.run(
      ['a', 'b'],
      AggregateOp.sum,
      attribute: 'due_date',
    );
    expect(sum.hasValue, isFalse);
    expect(sum.problem, AggregateProblem.notNumeric);
  });

  test('reports when nothing has the attribute', () async {
    final outcome = await aggregator.run(
      ['d'],
      AggregateOp.min,
      attribute: 'amount',
    );
    expect(outcome.hasValue, isFalse);
    expect(outcome.problem, AggregateProblem.noValues);
  });
}
