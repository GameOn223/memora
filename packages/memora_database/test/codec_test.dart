import 'package:memora_database/src/codec.dart';
import 'package:test/test.dart';

void main() {
  group('timestamps', () {
    test('store UTC milliseconds and read back as UTC', () {
      final local = DateTime(2026, 8, 31, 18, 30, 15, 123);
      final millis = toMillis(local);
      expect(millis, local.millisecondsSinceEpoch);

      final read = fromMillis(millis);
      expect(read.isUtc, isTrue);
      expect(read.isAtSameMomentAs(local), isTrue);
      expect(fromMillisOrNull(null), isNull);
      expect(fromMillisOrNull(millis), read);
    });
  });

  group('isoDateOnOrAfter', () {
    test('keeps a local midnight on the same day', () {
      expect(isoDateOnOrAfter(DateTime(2026, 10)), '2026-10-01');
      expect(isoDateOnOrAfter(DateTime(2026, 1, 9)), '2026-01-09');
    });

    test('moves any later time to the next day', () {
      expect(isoDateOnOrAfter(DateTime(2026, 10, 1, 0, 0, 1)), '2026-10-02');
      expect(isoDateOnOrAfter(DateTime(2026, 12, 31, 12)), '2027-01-01');
    });
  });

  group('JSON', () {
    test('encodes null as null and round-trips values', () {
      expect(encodeJson(null), isNull);
      expect(decodeJson(null), isNull);
      const value = {
        'a': [1, 2.5, 'x'],
        'b': true,
      };
      expect(decodeJson(encodeJson(value)), value);
    });

    test('blankToNull drops empty and whitespace strings', () {
      expect(blankToNull(null), isNull);
      expect(blankToNull(''), isNull);
      expect(blankToNull('  \n'), isNull);
      expect(blankToNull(' bill '), ' bill ');
    });
  });
}
