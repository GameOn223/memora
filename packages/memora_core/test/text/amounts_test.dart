import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

void main() {
  group('findAmounts', () {
    ParsedAmount single(String text) {
      final found = findAmounts(text);
      expect(found, hasLength(1), reason: 'in "$text"');
      return found.single;
    }

    final cases = <String, (double, String)>{
      '₹1,842': (1842, 'INR'),
      '₹ 1,842.50': (1842.5, 'INR'),
      'Rs. 1,842': (1842, 'INR'),
      'Rs 1842/-': (1842, 'INR'),
      'INR 1,24,900': (124900, 'INR'),
      r'$12.99': (12.99, 'USD'),
      'USD 12': (12, 'USD'),
      '€ 9,99': (9.99, 'EUR'),
      '£5': (5, 'GBP'),
      '1,842 INR': (1842, 'INR'),
      'Total: Rs.1,842.00': (1842, 'INR'),
      '1.234,56 EUR': (1234.56, 'EUR'),
      '9,99 €': (9.99, 'EUR'),
    };

    cases.forEach((text, expected) {
      test('reads "$text"', () {
        final amount = single(text);
        expect(amount.value, closeTo(expected.$1, 0.001));
        expect(amount.currency, expected.$2);
      });
    });

    test('keeps the raw match', () {
      expect(single('Amount due Rs. 1,842 by Friday').raw, 'Rs. 1,842');
    });

    test('ignores bare numbers and phone numbers', () {
      expect(findAmounts('Call 98450 12345 for help'), isEmpty);
      expect(findAmounts('Units consumed 342'), isEmpty);
      expect(findAmounts('Order 1842'), isEmpty);
    });

    test('returns amounts in order of appearance', () {
      final found = findAmounts(r'Subtotal ₹1,700 Tax ₹142 Total ₹1,842');
      expect(found.map((a) => a.value), [1700, 142, 1842]);
    });

    test('does not read letters ending in rs as rupees', () {
      expect(findAmounts('hours 12'), isEmpty);
    });

    test('rejects malformed digit grouping', () {
      expect(findAmounts('₹1,2,3'), isEmpty);
    });

    test('treats a bare /- suffix as the default currency', () {
      final found = findAmounts('Paid 500/-', defaultCurrency: 'INR');
      expect(found.single.value, 500);
      expect(found.single.currency, 'INR');
    });

    test('dollar sign follows a dollar default currency', () {
      expect(
        findAmounts(r'$20', defaultCurrency: 'CAD').single.currency,
        'CAD',
      );
      expect(findAmounts(r'$20').single.currency, 'USD');
    });
  });

  group('parseAmountExpression', () {
    final cases = <String, (double, String?)>{
      '2000': (2000, null),
      '2k': (2000, null),
      '2.5k': (2500, null),
      '₹2,000': (2000, 'INR'),
      '1.2 lakh': (120000, null),
      '3 lakhs': (300000, null),
      '1 crore': (10000000, null),
      '1cr': (10000000, null),
      r'$50': (50, 'USD'),
      'rs 500': (500, 'INR'),
      '50 dollars': (50, 'USD'),
      '2,000 rupees': (2000, 'INR'),
    };

    cases.forEach((text, expected) {
      test('reads "$text"', () {
        final amount = parseAmountExpression(text);
        expect(amount, isNotNull);
        expect(amount!.value, closeTo(expected.$1, 0.001));
        expect(amount.currency, expected.$2);
      });
    });

    test('returns null for text that is not an amount', () {
      expect(parseAmountExpression('reliance'), isNull);
      expect(parseAmountExpression(''), isNull);
      expect(parseAmountExpression('2000 bills'), isNull);
    });
  });

  group('normalizeCurrency', () {
    test('maps symbols and names to ISO codes', () {
      expect(normalizeCurrency('₹'), 'INR');
      expect(normalizeCurrency('Rs.'), 'INR');
      expect(normalizeCurrency(r'$'), 'USD');
      expect(normalizeCurrency('eur'), 'EUR');
      expect(normalizeCurrency(' gbp '), 'GBP');
      expect(normalizeCurrency(''), isNull);
      expect(normalizeCurrency(null), isNull);
      expect(normalizeCurrency('not money'), isNull);
    });
  });
}
