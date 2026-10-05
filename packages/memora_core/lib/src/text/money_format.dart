/// Display strings for money, such as `₹1,24,900` and `$12.99`.
library;

const _symbols = {'INR': '₹', 'USD': r'$', 'EUR': '€', 'GBP': '£'};

/// Formats [value] for display.
///
/// INR uses Indian digit grouping (`₹1,24,900`). USD, EUR and GBP use their
/// symbols with western grouping. Other ISO codes follow the number
/// (`1,234 JPY`), and a null currency gives a plain grouped number. Decimals
/// are shown only when the value has a fractional part, and then always two.
String formatMoney(double value, String? currency) {
  final code = currency?.toUpperCase();
  final cents = (value.abs() * 100).round();
  final whole = cents ~/ 100;
  final fraction = cents % 100;
  final grouped = code == 'INR'
      ? groupIndian(whole.toString())
      : groupWestern(whole.toString());
  final number = fraction == 0
      ? grouped
      : '$grouped.${fraction.toString().padLeft(2, '0')}';
  final sign = value < 0 && cents != 0 ? '-' : '';
  final symbol = _symbols[code];
  if (symbol != null) return '$sign$symbol$number';
  if (code == null || code.isEmpty) return '$sign$number';
  return '$sign$number $code';
}

/// Formats a number that is not money with western grouping and up to two
/// decimals.
String formatNumber(double value) => formatMoney(value, null);

/// `1234567` becomes `12,34,567`.
String groupIndian(String digits) {
  if (digits.length <= 3) return digits;
  final head = digits.substring(0, digits.length - 3);
  final tail = digits.substring(digits.length - 3);
  final parts = <String>[];
  for (var end = head.length; end > 0; end -= 2) {
    parts.insert(0, head.substring(end - 2 < 0 ? 0 : end - 2, end));
  }
  return '${parts.join(',')},$tail';
}

/// `1234567` becomes `1,234,567`.
String groupWestern(String digits) {
  final parts = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    parts.insert(0, digits.substring(end - 3 < 0 ? 0 : end - 3, end));
  }
  return parts.join(',');
}
