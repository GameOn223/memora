import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

void main() {
  group('needsMemories', () {
    test('anything in the first person is about their own things', () {
      for (final question in [
        'show me all my reliance bills',
        'when is my electricity bill due',
        'what did I pay for the laptop',
        'how much have we spent on flights',
        'did I save that booking',
        "what's mine from last september",
      ]) {
        expect(QuestionKind.needsMemories(question), isTrue, reason: question);
      }
    });

    test('words for the things Memora holds mean search', () {
      for (final question in [
        'any unpaid bills',
        'find the hotel reservation',
        'which receipts are from august',
        'the otp screenshot',
        'total amount on the invoice',
      ]) {
        expect(QuestionKind.needsMemories(question), isTrue, reason: question);
      }
    });

    test('plainly general questions get answered straight', () {
      for (final question in [
        'what is the capital of France',
        'what does kWh stand for',
        'convert 240 euros to rupees',
        'write a polite way to ask for an extension',
        'explain compound interest',
        'who wrote Dune',
        'is 91 a prime number',
      ]) {
        expect(QuestionKind.needsMemories(question), isFalse, reason: question);
      }
    });

    test('a bare question about the collection is a search', () {
      // Nothing else in these to be asking about.
      expect(QuestionKind.needsMemories('how many'), isTrue);
      expect(QuestionKind.needsMemories('show everything'), isTrue);
    });

    test('a long general question is not dragged in by one short word', () {
      expect(
        QuestionKind.needsMemories(
          'explain how a heat pump moves warmth from cold outside air',
        ),
        isFalse,
        reason: '"how" alone should not make a physics question a search',
      );
    });

    test('nothing to read is not a search', () {
      expect(QuestionKind.needsMemories(''), isFalse);
      expect(QuestionKind.needsMemories('   '), isFalse);
      expect(QuestionKind.needsMemories('?!'), isFalse);
    });

    test('case and punctuation do not matter', () {
      expect(QuestionKind.needsMemories('MY BILLS!'), isTrue);
      expect(QuestionKind.needsMemories('My-Bills?'), isTrue);
    });

    test('directAnswerIsFine is the other side of the same question', () {
      expect(QuestionKind.directAnswerIsFine('what is 2 plus 2'), isTrue);
      expect(QuestionKind.directAnswerIsFine('my bills'), isFalse);
    });
  });
}
