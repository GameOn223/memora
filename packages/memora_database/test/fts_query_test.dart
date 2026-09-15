import 'package:memora_database/src/fts_query.dart';
import 'package:test/test.dart';

void main() {
  group('ftsMatchExpression', () {
    test('quotes tokens and adds a prefix star from three letters', () {
      expect(
        ftsMatchExpression('Electricity bill TV'),
        '"electricity"* OR "bill"* OR "tv"',
      );
    });

    test('drops stopwords, single characters and repeats', () {
      expect(
        ftsMatchExpression('show me all the bills for a bill i saw'),
        '"bills"* OR "bill"*',
      );
    });

    test('returns null when nothing searchable is left', () {
      expect(ftsMatchExpression(''), isNull);
      expect(ftsMatchExpression('   '), isNull);
      expect(ftsMatchExpression('what was that from me?'), isNull);
      expect(ftsMatchExpression('!!! ... ---'), isNull);
    });

    test('splits on anything that is not a letter or digit', () {
      expect(
        ftsMatchExpression('Café-Zürich ₹12,000 #K4T9RB'),
        '"café"* OR "zürich"* OR "12" OR "000"* OR "k4t9rb"*',
      );
    });

    test('never lets FTS syntax through', () {
      final quotedOnly = RegExp(r'^"[^"\s]+"\*?( OR "[^"\s]+"\*?)*$');
      for (final input in [
        'bill" OR 1=1 --',
        'NEAR(',
        'summary:bill',
        'bill AND NOT receipt',
        '"unclosed',
        '^start*',
        '(gas OR water)',
        'col : {a b} NEAR/2',
      ]) {
        final expression = ftsMatchExpression(input);
        expect(expression, isNotNull, reason: input);
        expect(expression, matches(quotedOnly), reason: input);
      }
      expect(ftsMatchExpression('bill" OR 1=1 --'), '"bill"*');
      expect(ftsMatchExpression('NEAR('), '"near"*');
    });
  });
}
