import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

void main() {
  test('INR uses Indian grouping and shows paise only when present', () {
    expect(formatMoney(124900, 'INR'), '₹1,24,900');
    expect(formatMoney(1842, 'INR'), '₹1,842');
    expect(formatMoney(1842.5, 'INR'), '₹1,842.50');
    expect(formatMoney(12345678, 'INR'), '₹1,23,45,678');
    expect(formatMoney(999, 'INR'), '₹999');
    expect(formatMoney(0.5, 'INR'), '₹0.50');
  });

  test('USD, EUR and GBP use their symbols with western grouping', () {
    expect(formatMoney(12.99, 'USD'), r'$12.99');
    expect(formatMoney(1234567, 'USD'), r'$1,234,567');
    expect(formatMoney(9.99, 'EUR'), '€9.99');
    expect(formatMoney(5, 'GBP'), '£5');
  });

  test('other codes follow the number', () {
    expect(formatMoney(1234, 'JPY'), '1,234 JPY');
  });

  test('no currency gives a plain grouped number', () {
    expect(formatMoney(1234.5, null), '1,234.50');
    expect(formatMoney(42, null), '42');
  });

  test('negative values keep the sign in front', () {
    expect(formatMoney(-1842, 'INR'), '-₹1,842');
  });

  test('rounds to two decimals', () {
    expect(formatMoney(1878.3333, 'INR'), '₹1,878.33');
    expect(formatMoney(19.999, 'USD'), r'$20');
  });
}
