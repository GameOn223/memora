import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Converts a time to the UTC milliseconds stored in timestamp columns.
int toMillis(DateTime time) => time.millisecondsSinceEpoch;

/// Reads a timestamp column back as a UTC [DateTime].
DateTime fromMillis(int millis) =>
    DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

/// Like [fromMillis] for nullable columns.
DateTime? fromMillisOrNull(Object? millis) =>
    millis == null ? null : fromMillis(millis as int);

/// The first calendar date, as `YYYY-MM-DD`, whose local midnight is at or
/// after [instant].
///
/// Date attributes stand for whole days. A day counts as inside a
/// [start, end) range when its midnight is, so both bounds of a range map to
/// dates with this function and compare with `>=` and `<`.
String isoDateOnOrAfter(DateTime instant) {
  final local = instant.toLocal();
  var day = DateTime(local.year, local.month, local.day);
  if (day.isBefore(local)) {
    day = DateTime(local.year, local.month, local.day + 1);
  }
  final month = day.month.toString().padLeft(2, '0');
  final date = day.day.toString().padLeft(2, '0');
  return '${day.year.toString().padLeft(4, '0')}-$month-$date';
}

/// Encodes a vector for the `embeddings.vector` column: float32 values in
/// little-endian order, four bytes each.
Uint8List encodeVector(Float32List vector) {
  final bytes = ByteData(vector.length * 4);
  for (var i = 0; i < vector.length; i++) {
    bytes.setFloat32(i * 4, vector[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// Decodes an `embeddings.vector` blob into a new vector.
///
/// The bytes are copied, so a blob that starts at an odd offset inside a
/// larger buffer is fine.
Float32List decodeVector(Uint8List bytes) {
  if (bytes.length % 4 != 0) {
    throw FormatException(
      'A vector blob must be a whole number of float32 values, '
      'got ${bytes.length} bytes',
    );
  }
  final vector = Float32List(bytes.length ~/ 4);
  decodeVectorInto(bytes, vector);
  return vector;
}

/// Decodes [bytes] into [target], which must hold exactly
/// `bytes.length ~/ 4` values. Lets a scan reuse one buffer for every row.
void decodeVectorInto(Uint8List bytes, Float32List target) {
  if (Endian.host == Endian.little) {
    target.buffer
        .asUint8List(target.offsetInBytes, target.lengthInBytes)
        .setAll(0, bytes);
    return;
  }
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < target.length; i++) {
    target[i] = data.getFloat32(i * 4, Endian.little);
  }
}

/// Returns [vector] scaled to unit length. A zero vector comes back as zeros.
Float32List normalizeVector(Float32List vector) {
  var sum = 0.0;
  for (final value in vector) {
    sum += value * value;
  }
  final result = Float32List(vector.length);
  if (sum == 0 || sum.isNaN) return result;
  final scale = 1 / sqrt(sum);
  for (var i = 0; i < vector.length; i++) {
    result[i] = vector[i] * scale;
  }
  return result;
}

/// Encodes a JSON column value. Null stays null.
String? encodeJson(Object? value) => value == null ? null : jsonEncode(value);

/// Decodes a JSON column value. Null stays null.
Object? decodeJson(String? text) => text == null ? null : jsonDecode(text);

/// Returns null for null, empty or whitespace-only text.
String? blankToNull(String? text) =>
    text == null || text.trim().isEmpty ? null : text;
