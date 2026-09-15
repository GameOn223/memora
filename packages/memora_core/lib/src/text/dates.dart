/// Finding and parsing calendar dates in text.
library;

import 'package:meta/meta.dart';

/// A calendar date found in text. [date] is local midnight.
@immutable
class ParsedDate {
  const ParsedDate({required this.date, required this.raw});

  final DateTime date;

  /// The matched text, for example `31 Aug 2026`.
  final String raw;

  @override
  bool operator ==(Object other) =>
      other is ParsedDate && other.date == date && other.raw == raw;

  @override
  int get hashCode => Object.hash(date, raw);

  @override
  String toString() => 'ParsedDate(${isoDate(date)}, "$raw")';
}

const _monthNumbers = {
  'jan': 1,
  'january': 1,
  'feb': 2,
  'february': 2,
  'mar': 3,
  'march': 3,
  'apr': 4,
  'april': 4,
  'may': 5,
  'jun': 6,
  'june': 6,
  'jul': 7,
  'july': 7,
  'aug': 8,
  'august': 8,
  'sep': 9,
  'sept': 9,
  'september': 9,
  'oct': 10,
  'october': 10,
  'nov': 11,
  'november': 11,
  'dec': 12,
  'december': 12,
};

/// Short English month names, index 0 is January.
const monthAbbreviations = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Looks up a month by English name or abbreviation, case-insensitively.
int? monthNumber(String name) => _monthNumbers[name.toLowerCase()];

/// Regular expression source matching any English month name. No capturing
/// groups.
const monthNamePattern =
    '(?:january|february|march|april|may|june|july|august|september|'
    'october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|'
    'dec)';

const _ordinal = '(?:st|nd|rd|th)?';

final _isoPattern = RegExp(
  r'(?<![\d/.-])(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?![\d])',
);

final _numericPattern = RegExp(
  r'(?<![\d/.-])(\d{1,2})([/.-])(\d{1,2})\2(\d{4}|\d{2})(?![\d])',
);

final _dayMonthYear = RegExp(
  '(?<![a-z0-9])(\\d{1,2})$_ordinal[\\s-]+($monthNamePattern)\\.?,?[\\s-]+'
  '(\\d{4})(?![\\d])',
  caseSensitive: false,
);

final _monthDayYear = RegExp(
  '(?<![a-z0-9])($monthNamePattern)\\.?\\s+(\\d{1,2})$_ordinal,?\\s+(\\d{4})'
  '(?![\\d])',
  caseSensitive: false,
);

final _dayMonth = RegExp(
  '(?<![a-z0-9])(\\d{1,2})$_ordinal[\\s-]+($monthNamePattern)(?![a-z])',
  caseSensitive: false,
);

final _monthDay = RegExp(
  '(?<![a-z0-9])($monthNamePattern)\\.?\\s+(\\d{1,2})$_ordinal(?![\\d:a-z])',
  caseSensitive: false,
);

/// Finds dates in [text], in order of appearance.
///
/// Understands `31/08/2026`, `31-08-2026`, `31.08.2026`, `2026-08-31`,
/// `31 Aug 2026`, `31st August 2026`, `Aug 31, 2026` and `August 31 2026`.
/// Numeric dates are read day first unless [dayFirst] is false, and a part
/// larger than 12 settles the order either way. A date without a year, such
/// as `31 Aug`, gets the year that makes it the most recent such date no more
/// than six months after [reference]. Impossible dates are skipped.
List<ParsedDate> findDates(
  String text, {
  required DateTime reference,
  bool dayFirst = true,
}) {
  final found = <({int start, int end, ParsedDate date})>[];

  void add(Match m, DateTime? date) {
    if (date == null) return;
    final overlaps = found.any((f) => m.start < f.end && f.start < m.end);
    if (overlaps) return;
    found.add((
      start: m.start,
      end: m.end,
      date: ParsedDate(date: date, raw: m[0]!),
    ));
  }

  for (final m in _isoPattern.allMatches(text)) {
    add(m, _validDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)));
  }
  for (final m in _numericPattern.allMatches(text)) {
    final a = int.parse(m[1]!);
    final b = int.parse(m[3]!);
    var year = int.parse(m[4]!);
    if (m[4]!.length == 2) year += 2000;
    final monthFirst = dayFirst ? (b > 12 && a <= 12) : !(a > 12 && b <= 12);
    add(m, monthFirst ? _validDate(year, a, b) : _validDate(year, b, a));
  }
  for (final m in _dayMonthYear.allMatches(text)) {
    add(m, _validDate(int.parse(m[3]!), monthNumber(m[2]!)!, int.parse(m[1]!)));
  }
  for (final m in _monthDayYear.allMatches(text)) {
    add(m, _validDate(int.parse(m[3]!), monthNumber(m[1]!)!, int.parse(m[2]!)));
  }
  for (final m in _dayMonth.allMatches(text)) {
    add(m, _yearless(monthNumber(m[2]!)!, int.parse(m[1]!), reference));
  }
  for (final m in _monthDay.allMatches(text)) {
    add(m, _yearless(monthNumber(m[1]!)!, int.parse(m[2]!), reference));
  }

  found.sort((a, b) => a.start.compareTo(b.start));
  return [for (final f in found) f.date];
}

DateTime? _validDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

DateTime? _yearless(int month, int day, DateTime reference) {
  final limit = DateTime(
    reference.year,
    reference.month + 6,
    reference.day,
  ).add(const Duration(days: 1));
  for (var year = reference.year + 1; year >= reference.year - 1; year--) {
    final date = _validDate(year, month, day);
    if (date != null && date.isBefore(limit)) return date;
  }
  return null;
}

final _isoPrefix = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:$|[T ])');

/// Parses `YYYY-MM-DD`, or the date part of a full ISO timestamp, into local
/// midnight. Returns null for anything else, including impossible dates.
DateTime? parseIsoDate(String value) {
  final trimmed = value.trim();
  final m = _isoPrefix.firstMatch(trimmed);
  if (m == null) return null;
  if (trimmed.length > 10 && DateTime.tryParse(trimmed) == null) return null;
  return _validDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// `YYYY-MM-DD` for the local calendar date of [d].
String isoDate(DateTime d) {
  final local = d.toLocal();
  final m = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-$m-$day';
}

/// A short readable date such as `31 Aug 2026`.
String displayDate(DateTime d) {
  final local = d.toLocal();
  return '${local.day} ${monthAbbreviations[local.month - 1]} ${local.year}';
}

/// A month and year such as `Aug 2026`.
String displayMonth(DateTime d) {
  final local = d.toLocal();
  return '${monthAbbreviations[local.month - 1]} ${local.year}';
}
