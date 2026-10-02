import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

void main() {
  const parser = QueryParser();
  // A Tuesday.
  final now = DateTime(2026, 9, 15, 10, 30);

  ParsedQuery parse(String text, {DateTime? at}) =>
      parser.parse(text, now: at ?? now);

  group('examples from the docs', () {
    test('reliance bills over ₹2000 from last year', () {
      final p = parse('show me all reliance bills over ₹2000 from last year');
      expect(p.query.categories, {'utility_bill', 'invoice'});
      expect(p.query.attributes, [
        const AttributeFilter(type: 'amount', min: 2000, currency: 'INR'),
      ]);
      expect(p.query.takenBetween, DateRange.year(2025));
      expect(p.remainingText, 'reliance');
      expect(p.query.text, 'reliance');
      expect(p.aggregate, isNull);
    });

    test('laptop comparison i saw last month', () {
      final p = parse('find that laptop comparison i saw last month');
      expect(p.query.takenBetween, DateRange.month(2026, 8));
      expect(p.query.categories, isEmpty);
      expect(p.query.attributes, isEmpty);
      expect(p.remainingText, 'laptop comparison');
    });

    test('which one was highest?', () {
      final p = parse('which one was highest?');
      expect(p.aggregate, const AggregateIntent(AggregateOp.max));
      expect(p.aggregate!.attribute, 'amount');
      expect(p.remainingText, '');
      expect(p.query.text, isNull);
      expect(p.query.hasFilters, isFalse);
    });
  });

  group('dates', () {
    DateRange? range(String text, {DateTime? at}) =>
        parse(text, at: at).query.takenBetween;

    test('relative days, weeks, months and years', () {
      expect(
        range('receipts from today'),
        DateRange.day(DateTime(2026, 9, 15)),
      );
      expect(range('yesterday'), DateRange.day(DateTime(2026, 9, 14)));
      expect(
        range('this week'),
        DateRange(start: DateTime(2026, 9, 14), end: DateTime(2026, 9, 21)),
      );
      expect(
        range('last week'),
        DateRange(start: DateTime(2026, 9, 7), end: DateTime(2026, 9, 14)),
      );
      expect(range('this month'), DateRange.month(2026, 9));
      expect(range('last month'), DateRange.month(2026, 8));
      expect(range('this year'), DateRange.year(2026));
      expect(range('last year'), DateRange.year(2025));
      expect(
        range('last 7 days'),
        DateRange(start: DateTime(2026, 9, 9), end: DateTime(2026, 9, 16)),
      );
    });

    test('month names pick the most recent one that is not in the future', () {
      expect(range('bills in august'), DateRange.month(2026, 8));
      expect(range('august'), DateRange.month(2026, 8));
      expect(range('in september'), DateRange.month(2026, 9));
      expect(range('in october'), DateRange.month(2025, 10));
      expect(
        range('in august', at: DateTime(2026, 7, 10)),
        DateRange.month(2025, 8),
      );
      expect(range('august 2024'), DateRange.month(2024, 8));
      expect(range('aug 2025 bills'), DateRange.month(2025, 8));
      expect(range('in 2024'), DateRange.year(2024));
    });

    test('may only counts as a month when it clearly is one', () {
      expect(range('bills in may'), DateRange.month(2026, 5));
      expect(range('may i see my bills'), isNull);
    });

    test('last sunday is the most recent sunday before today', () {
      expect(range('last sunday'), DateRange.day(DateTime(2026, 9, 13)));
      expect(
        range('last tuesday'),
        DateRange.day(DateTime(2026, 9, 8)),
        reason: 'today is a Tuesday, so the one before',
      );
    });

    test('around, since and before a month', () {
      expect(
        range('around july'),
        DateRange(start: DateTime(2026, 6, 16), end: DateTime(2026, 8, 16)),
      );
      expect(range('since july'), DateRange(start: DateTime(2026, 7)));
      expect(range('before july'), DateRange(end: DateTime(2026, 7)));
    });
  });

  group('amounts', () {
    AttributeFilter amountFilter(String text) =>
        parse(text).query.attributes.single;

    test('lower bounds', () {
      expect(
        amountFilter('bills above 2k'),
        const AttributeFilter(type: 'amount', min: 2000),
      );
      expect(amountFilter('more than 1.5 lakh').min, 150000);
      expect(amountFilter('greater than 500').min, 500);
      expect(amountFilter('> 300').min, 300);
    });

    test('upper bounds keep the currency', () {
      expect(
        amountFilter(r'receipts under $50'),
        const AttributeFilter(type: 'amount', max: 50, currency: 'USD'),
      );
      expect(amountFilter('below rs 999').currency, 'INR');
      expect(amountFilter('less than 1 crore').max, 10000000);
    });

    test('between two amounts', () {
      expect(
        amountFilter('between 1000 and 2,500'),
        const AttributeFilter(type: 'amount', min: 1000, max: 2500),
      );
    });

    test('numbers that are not amounts are left alone', () {
      final p = parse('bills under 2 weeks old');
      expect(p.query.attributes, isEmpty);
    });
  });

  group('categories', () {
    Set<String> categories(String text) => parse(text).query.categories;

    test('maps everyday words to categories', () {
      expect(categories('my receipts'), {'receipt'});
      expect(categories('bookings'), {'booking', 'ticket'});
      expect(categories('flight tickets'), {'booking', 'ticket'});
      expect(categories('places i saved'), {'place', 'map'});
      expect(categories('maps'), {'place', 'map'});
      expect(categories('chats with rahul'), {'chat'});
      expect(categories('code snippets'), {'code'});
      expect(categories('shopping'), {'product', 'comparison'});
      expect(categories('a sunset'), isEmpty);
    });
  });

  group('superlatives', () {
    AggregateIntent? intent(String text) => parse(text).aggregate;

    test('map to aggregate operations on amount', () {
      expect(intent('most expensive bill')!.op, AggregateOp.max);
      expect(intent('the biggest one')!.op, AggregateOp.max);
      expect(intent('cheapest receipt')!.op, AggregateOp.min);
      expect(intent('lowest')!.op, AggregateOp.min);
      expect(intent('total spent on swiggy')!.op, AggregateOp.sum);
      expect(intent('how much did i spend')!.op, AggregateOp.sum);
      expect(intent('average bill')!.op, AggregateOp.avg);
      expect(intent('how many bookings')!.op, AggregateOp.count);
      expect(intent('latest bill')!.op, AggregateOp.latest);
      expect(intent('most recent receipt')!.op, AggregateOp.latest);
      expect(intent('the last one')!.op, AggregateOp.latest);
      expect(intent('bills last month'), isNull);
    });

    test('aggregates ask for a wider search', () {
      expect(parse('highest bill').query.limit, RetrievalQuery.maxLimit);
      expect(parse('bills').query.limit, 20);
    });
  });

  test('remaining text drops matched phrases and filler words', () {
    final p = parse('Show me the electricity bills from Swiggy in August!');
    expect(p.remainingText, 'electricity swiggy');
    expect(p.query.categories, {'utility_bill', 'invoice'});
    expect(p.query.takenBetween, DateRange.month(2026, 8));
  });
}
