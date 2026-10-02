import 'package:memora_database/src/fold.dart';
import 'package:test/test.dart';

void main() {
  group('foldForMatch', () {
    test('lowercases and trims', () {
      expect(foldForMatch('  Reliance Energy '), 'reliance energy');
      expect(foldForMatch(''), '');
      expect(foldForMatch('   '), '');
    });

    test('collapses runs of whitespace', () {
      expect(foldForMatch('Air \t India\n\nExpress'), 'air india express');
    });

    test('takes accents off Latin letters', () {
      expect(foldForMatch('Café'), 'cafe');
      expect(foldForMatch('CAFÉ'), 'cafe');
      expect(foldForMatch('Zürich'), 'zurich');
      expect(foldForMatch('Ångström'), 'angstrom');
      expect(foldForMatch('Škoda'), 'skoda');
      expect(foldForMatch('Łódź'), 'łodz');
      expect(foldForMatch('Señor Niño'), 'senor nino');
    });

    test('drops combining marks that stand on their own', () {
      expect(foldForMatch('café'), 'cafe');
      expect(foldForMatch('ñino'), 'nino');
    });

    test('leaves other scripts and digits alone', () {
      expect(foldForMatch('बिजली बिल'), 'बिजली बिल');
      expect(foldForMatch('K4T9RB'), 'k4t9rb');
      expect(foldForMatch('₹1,842'), '₹1,842');
    });
  });
}
