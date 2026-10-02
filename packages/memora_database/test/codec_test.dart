import 'dart:typed_data';

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

  group('vectors', () {
    test('encode as little-endian float32', () {
      final bytes = encodeVector(Float32List.fromList([1, -2.5]));
      expect(bytes, [0, 0, 128, 63, 0, 0, 32, 192]);
    });

    test('round-trip exactly', () {
      final vector = Float32List.fromList([0.1, -0.333, 1e-7, 42]);
      expect(decodeVector(encodeVector(vector)), vector);
      expect(decodeVector(Uint8List(0)), isEmpty);
    });

    test('decode a blob that sits at an odd offset', () {
      final backing = Uint8List(9);
      backing.setAll(1, encodeVector(Float32List.fromList([0.5, 2])));
      final view = Uint8List.sublistView(backing, 1);
      expect(decodeVector(view), [0.5, 2]);
    });

    test('normalize to unit length and leave zero vectors alone', () {
      final unit = normalizeVector(Float32List.fromList([3, 4]));
      expect(unit[0], closeTo(0.6, 1e-6));
      expect(unit[1], closeTo(0.8, 1e-6));
      expect(normalizeVector(Float32List(3)), [0, 0, 0]);
    });

    test('reject blobs that are not whole float32 values', () {
      expect(() => decodeVector(Uint8List(6)), throwsFormatException);
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
