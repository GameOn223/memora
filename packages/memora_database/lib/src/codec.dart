import 'dart:convert';

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

/// Encodes a JSON column value. Null stays null.
String? encodeJson(Object? value) => value == null ? null : jsonEncode(value);

/// Decodes a JSON column value. Null stays null.
Object? decodeJson(String? text) => text == null ? null : jsonDecode(text);

/// Returns null for null, empty or whitespace-only text.
String? blankToNull(String? text) =>
    text == null || text.trim().isEmpty ? null : text;
