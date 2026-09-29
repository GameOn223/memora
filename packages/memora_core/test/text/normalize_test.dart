import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

void main() {
  group('foldForMatch', () {
    test('lowercases, folds accents and collapses whitespace', () {
      expect(foldForMatch('  Café   Coffee Day '), 'cafe coffee day');
      expect(foldForMatch('SÃO PAULO'), 'sao paulo');
      expect(foldForMatch('Łódź'), 'lodz');
      expect(foldForMatch('Straße'), 'strasse');
    });

    test('strips combining marks', () {
      expect(foldForMatch('Café'), 'cafe');
    });

    test('leaves non-Latin scripts alone', () {
      expect(foldForMatch('रिलायंस'), 'रिलायंस');
    });
  });

  group('searchTokens', () {
    test('keeps letters and digits and drops stopwords', () {
      expect(searchTokens('Show me the Reliance bill, from August!'), [
        'reliance',
        'bill',
        'august',
      ]);
    });

    test('drops single characters and folds accents', () {
      expect(searchTokens('a café x 42'), ['cafe', '42']);
    });
  });
}
