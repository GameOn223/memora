/// Finding and parsing money amounts in OCR text and search queries.
library;

import 'package:meta/meta.dart';

/// A money amount found in text.
@immutable
class ParsedAmount {
  const ParsedAmount({required this.value, required this.raw, this.currency});

  final double value;

  /// ISO 4217 code, or null when the text gave no currency.
  final String? currency;

  /// The matched text, for example `Rs. 1,842`.
  final String raw;

  @override
  bool operator ==(Object other) =>
      other is ParsedAmount &&
      other.value == value &&
      other.currency == currency &&
      other.raw == raw;

  @override
  int get hashCode => Object.hash(value, currency, raw);

  @override
  String toString() => 'ParsedAmount($value $currency, "$raw")';
}

const _rupeeCurrencies = {'INR', 'PKR', 'NPR', 'LKR'};
const _dollarCurrencies = {'USD', 'CAD', 'AUD', 'NZD', 'SGD', 'HKD'};
const _codes =
    'inr|usd|eur|gbp|jpy|aed|sgd|aud|cad|chf|cny|hkd|nzd|sar|pkr|npr|lkr';

final _amountPattern = RegExp(
  // A currency marker, then the number.
  '(?<![a-z0-9])(₹|rs\\.?|us\\\$|\\\$|€|£|$_codes)\\s*(\\d[\\d,.]*\\d|\\d)'
  '(?![\\d])(?:\\s*/-)?'
  // Or the number, then a currency marker that does not start another amount.
  '|(?<![\\d,.])(\\d[\\d,.]*\\d|\\d)\\s*(₹|€|/-|rupees?(?![a-z])|rs\\.?(?![a-z])|'
  '(?:$_codes)(?![a-z]))(?!\\s*\\d)',
  caseSensitive: false,
);

/// Finds money amounts in [text], in order of appearance.
///
/// Recognizes `₹`, `Rs`, `$`, `€`, `£`, ISO codes before or after the
/// number, and the Indian `/-` suffix. Indian (`1,24,900`) and western
/// (`124,900`) grouping both parse, and a comma is a decimal point when it is
/// followed by exactly two digits and there is no dot (`€ 9,99`). Bare
/// numbers without a currency marker are ignored, so phone numbers and
/// quantities are not mistaken for money.
List<ParsedAmount> findAmounts(String text, {String defaultCurrency = 'INR'}) {
  final result = <ParsedAmount>[];
  for (final match in _amountPattern.allMatches(text)) {
    final marker = match[1] ?? match[4]!;
    final digits = match[2] ?? match[3]!;
    final value = parseLocalizedNumber(digits);
    if (value == null) continue;
    result.add(
      ParsedAmount(
        value: value,
        currency: _currencyForMarker(marker, defaultCurrency),
        raw: match[0]!.trim(),
      ),
    );
  }
  return result;
}

String? _currencyForMarker(String marker, String defaultCurrency) {
  final m = marker.toLowerCase();
  final fallback = defaultCurrency.toUpperCase();
  if (m == '₹') return 'INR';
  if (m == '/-') return fallback;
  if (m.startsWith('rs') || m.startsWith('rupee')) {
    return _rupeeCurrencies.contains(fallback) ? fallback : 'INR';
  }
  if (m == r'$') {
    return _dollarCurrencies.contains(fallback) ? fallback : 'USD';
  }
  if (m == r'us$') return 'USD';
  if (m == '€') return 'EUR';
  if (m == '£') return 'GBP';
  return m.toUpperCase();
}

/// Parses a number written with thousands separators and a decimal point or
/// comma. Returns null when the grouping is malformed, such as `1,2,3`.
double? parseLocalizedNumber(String raw) {
  final s = raw.trim();
  if (s.isEmpty || !RegExp(r'^\d[\d,.]*$').hasMatch(s)) return null;
  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  String integer;
  var fraction = '';
  String? groupSeparator;

  if (lastComma >= 0 && lastDot >= 0) {
    final decimalAt = lastComma > lastDot ? lastComma : lastDot;
    groupSeparator = lastComma > lastDot ? '.' : ',';
    integer = s.substring(0, decimalAt);
    fraction = s.substring(decimalAt + 1);
    if (integer.contains(s[decimalAt])) return null;
  } else if (lastComma >= 0) {
    final after = s.length - lastComma - 1;
    if (','.allMatches(s).length == 1 && after == 2) {
      integer = s.substring(0, lastComma);
      fraction = s.substring(lastComma + 1);
    } else {
      integer = s;
      groupSeparator = ',';
    }
  } else if (lastDot >= 0) {
    final after = s.length - lastDot - 1;
    if ('.'.allMatches(s).length == 1 && after <= 2) {
      integer = s.substring(0, lastDot);
      fraction = s.substring(lastDot + 1);
    } else {
      integer = s;
      groupSeparator = '.';
    }
  } else {
    integer = s;
  }

  if (fraction.isNotEmpty && !RegExp(r'^\d{1,2}$').hasMatch(fraction)) {
    return null;
  }
  if (integer.isEmpty) return null;
  if (groupSeparator != null && integer.contains(groupSeparator)) {
    if (!_validGrouping(integer.split(groupSeparator))) return null;
    integer = integer.replaceAll(groupSeparator, '');
  }
  if (!RegExp(r'^\d+$').hasMatch(integer)) return null;
  return double.parse(fraction.isEmpty ? integer : '$integer.$fraction');
}

bool _validGrouping(List<String> groups) {
  if (groups.length < 2) return true;
  if (!RegExp(r'^\d{1,3}$').hasMatch(groups.first)) return false;
  if (!RegExp(r'^\d{3}$').hasMatch(groups.last)) return false;
  final middle = groups.sublist(1, groups.length - 1);
  if (middle.isEmpty) return true;
  final width = middle.first.length;
  return (width == 2 || width == 3) &&
      middle.every((g) => g.length == width && RegExp(r'^\d+$').hasMatch(g));
}

const _multipliers = {
  'k': 1e3,
  'thousand': 1e3,
  'lakh': 1e5,
  'lakhs': 1e5,
  'lac': 1e5,
  'lacs': 1e5,
  'crore': 1e7,
  'crores': 1e7,
  'cr': 1e7,
  'm': 1e6,
  'mn': 1e6,
  'million': 1e6,
};

const _prefixMarker = r'₹|rs\.?|inr|us\$|usd|\$|€|eur|£|gbp';
const _multiplier = r'k|thousand|lakhs?|lacs?|crores?|cr|mn|million|m';
const _suffixMarker = r'rupees?|rs\.?|inr|dollars?|usd|euros?|eur|pounds?|gbp';

/// Regular expression source for an amount in a query, such as `₹2,000`,
/// `2.5k` or `1 lakh`. Use it with `caseSensitive: false`. It has no
/// capturing groups, so it can be embedded in larger patterns.
const amountExpressionPattern =
    '(?:(?:$_prefixMarker)\\s*)?\\d[\\d,]*(?:\\.\\d+)?'
    '(?:\\s*(?:$_multiplier)(?![a-z]))?'
    '(?:\\s*(?:$_suffixMarker)(?![a-z]))?';

final _expression = RegExp(
  '^(?:($_prefixMarker)\\s*)?(\\d[\\d,]*(?:\\.\\d+)?)'
  '\\s*($_multiplier)?\\s*($_suffixMarker)?\$',
  caseSensitive: false,
);

/// Parses an amount the way people type it in a question: `2000`, `2k`,
/// `2.5k`, `₹2,000`, `1.2 lakh`, `3 lakhs`, `1 crore`, `1cr`, `$50`,
/// `50 dollars`. The whole string must be the amount. A number with no
/// currency marker has a null currency.
ParsedAmount? parseAmountExpression(
  String text, {
  String defaultCurrency = 'INR',
}) {
  final trimmed = text.trim();
  final match = _expression.firstMatch(trimmed);
  if (match == null) return null;
  final number = double.tryParse(match[2]!.replaceAll(',', ''));
  if (number == null) return null;
  final multiplier = match[3] == null
      ? 1.0
      : _multipliers[match[3]!.toLowerCase()]!;
  final marker = match[1] ?? match[4];
  String? currency;
  if (marker != null) {
    final m = marker.toLowerCase();
    currency = switch (m) {
      _ when m.startsWith('dollar') => _currencyForMarker(
        r'$',
        defaultCurrency,
      ),
      _ when m.startsWith('euro') => 'EUR',
      _ when m.startsWith('pound') => 'GBP',
      _ => _currencyForMarker(m, defaultCurrency),
    };
  }
  return ParsedAmount(
    value: number * multiplier,
    currency: currency,
    raw: trimmed,
  );
}

/// Turns what a model or a person wrote as a currency into an ISO 4217 code:
/// `₹` and `Rs` become `INR`, `$` becomes `USD`, `eur` becomes `EUR`.
/// Returns null when it isn't recognizable.
String? normalizeCurrency(String? value) {
  if (value == null) return null;
  final v = value.trim().toUpperCase();
  if (v.isEmpty) return null;
  switch (v) {
    case '₹' || 'RS' || 'RS.' || 'RUPEE' || 'RUPEES':
      return 'INR';
    case r'$' || r'US$' || 'DOLLAR' || 'DOLLARS':
      return 'USD';
    case '€' || 'EURO' || 'EUROS':
      return 'EUR';
    case '£' || 'POUND' || 'POUNDS':
      return 'GBP';
  }
  return RegExp(r'^[A-Z]{3}$').hasMatch(v) ? v : null;
}
