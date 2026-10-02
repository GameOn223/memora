import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

void main() {
  final reference = DateTime(2026, 9, 15);

  group('findDates', () {
    final cases = <String, DateTime>{
      '31/08/2026': DateTime(2026, 8, 31),
      '31-08-2026': DateTime(2026, 8, 31),
      '31.08.2026': DateTime(2026, 8, 31),
      '2026-08-31': DateTime(2026, 8, 31),
      '31 Aug 2026': DateTime(2026, 8, 31),
      '31st August 2026': DateTime(2026, 8, 31),
      'Aug 31, 2026': DateTime(2026, 8, 31),
      'August 31 2026': DateTime(2026, 8, 31),
      '08/31/2026': DateTime(2026, 8, 31),
      '31 Aug': DateTime(2026, 8, 31),
      '5-Oct-2026': DateTime(2026, 10, 5),
      '02/03/26': DateTime(2026, 3, 2),
    };

    cases.forEach((text, expected) {
      test('reads "$text"', () {
        final found = findDates(text, reference: reference);
        expect(found, hasLength(1), reason: 'in "$text"');
        expect(found.single.date, expected);
      });
    });

    test('keeps the raw match', () {
      final found = findDates('Due date: 31 Aug 2026.', reference: reference);
      expect(found.single.raw, '31 Aug 2026');
    });

    test('skips invalid dates', () {
      expect(findDates('31/02/2026', reference: reference), isEmpty);
      expect(findDates('2026-13-01', reference: reference), isEmpty);
    });

    test('month-first order when dayFirst is false', () {
      final found = findDates(
        '02/03/2026',
        reference: reference,
        dayFirst: false,
      );
      expect(found.single.date, DateTime(2026, 2, 3));
    });

    test('a yearless date is never more than six months ahead', () {
      expect(
        findDates('15 Jan', reference: reference).single.date,
        DateTime(2027, 1, 15),
      );
      expect(
        findDates('20 Apr', reference: reference).single.date,
        DateTime(2026, 4, 20),
      );
      expect(
        findDates('Dec 1', reference: reference).single.date,
        DateTime(2026, 12, 1),
      );
    });

    test('finds several dates in order without double counting', () {
      final found = findDates(
        'Bill date 01/08/2026, due 31 Aug 2026, paid on Aug 30',
        reference: reference,
      );
      expect(found.map((d) => d.date), [
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 31),
        DateTime(2026, 8, 30),
      ]);
    });

    test('ignores times, amounts and phone numbers', () {
      expect(
        findDates('9:41 ₹1,842 call 98450 12345', reference: reference),
        isEmpty,
      );
    });
  });

  group('parseIsoDate', () {
    test('accepts dates and timestamps', () {
      expect(parseIsoDate('2026-08-31'), DateTime(2026, 8, 31));
      expect(parseIsoDate(' 2026-08-31 '), DateTime(2026, 8, 31));
      expect(parseIsoDate('2026-08-31T10:15:00Z'), DateTime(2026, 8, 31));
      expect(parseIsoDate('2026-08-31 10:15'), DateTime(2026, 8, 31));
    });

    test('rejects anything else', () {
      expect(parseIsoDate('2026-13-01'), isNull);
      expect(parseIsoDate('2026-02-30'), isNull);
      expect(parseIsoDate('31/08/2026'), isNull);
      expect(parseIsoDate(''), isNull);
      expect(parseIsoDate('2026-08-31junk'), isNull);
    });
  });

  test('isoDate pads month and day', () {
    expect(isoDate(DateTime(2026, 3, 7)), '2026-03-07');
  });

  test('displayDate and displayMonth are short and readable', () {
    expect(displayDate(DateTime(2026, 8, 31)), '31 Aug 2026');
    expect(displayMonth(DateTime(2026, 8, 31)), 'Aug 2026');
  });
}
