import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

const _vocabLines = [
  '[PAD]',
  '[UNK]',
  '[CLS]',
  '[SEP]',
  '[MASK]',
  'hello',
  ',',
  'un',
  '##aff',
  '##able',
  'world',
  '!',
  'cafe',
  'the',
  'a',
  '##s',
  'run',
  '##ning',
  'quick',
  'brown',
  'fox',
  '.',
  "'",
  's',
  'dog',
  '1',
  '2',
  '3',
  'x',
  '##y',
];

void main() {
  final tokenizer = WordPieceTokenizer.fromVocabLines(_vocabLines);

  List<String> tokens(EncodedText encoded) => [
    for (final id in encoded.inputIds) _vocabLines[id],
  ];

  test('the test vocabulary has 30 tokens', () {
    expect(_vocabLines, hasLength(30));
  });

  test('splits punctuation and word pieces', () {
    final encoded = tokenizer.encode('Hello, unaffable world!');
    expect(tokens(encoded), [
      '[CLS]',
      'hello',
      ',',
      'un',
      '##aff',
      '##able',
      'world',
      '!',
      '[SEP]',
    ]);
    expect(encoded.attentionMask, everyElement(1));
    expect(encoded.tokenTypeIds, everyElement(0));
    expect(encoded.tokenTypeIds, hasLength(9));
  });

  test('folds accents and case', () {
    expect(tokens(tokenizer.encode('CAFÉ')), ['[CLS]', 'cafe', '[SEP]']);
    expect(tokens(tokenizer.encode('Café')), ['[CLS]', 'cafe', '[SEP]']);
  });

  test('unknown words become [UNK]', () {
    expect(tokenizer.tokenize('zebra running'), ['[UNK]', 'run', '##ning']);
    expect(tokenizer.tokenize('x' * 101), ['[UNK]']);
  });

  test('CJK ideographs are separate tokens', () {
    expect(tokenizer.tokenize('你好dog'), ['[UNK]', '[UNK]', 'dog']);
  });

  test('control characters are dropped and whitespace splits', () {
    expect(tokenizer.tokenize('hello\tworld​'), ['hello', 'world']);
  });

  test('truncation keeps [SEP] last', () {
    final short = WordPieceTokenizer.fromVocabLines(_vocabLines, maxLength: 5);
    final encoded = short.encode('the quick brown fox dog');
    expect(tokens(encoded), ['[CLS]', 'the', 'quick', 'brown', '[SEP]']);
  });

  test('batch encoding pads to the longest row', () {
    final batch = tokenizer.encodeBatch(['hello', 'hello world !']);
    expect(batch[0].inputIds, [2, 5, 3, 0, 0]);
    expect(batch[0].attentionMask, [1, 1, 1, 0, 0]);
    expect(batch[0].tokenTypeIds, [0, 0, 0, 0, 0]);
    expect(batch[1].inputIds, [2, 5, 10, 11, 3]);
    expect(batch[1].attentionMask, [1, 1, 1, 1, 1]);
  });

  test('vocabulary lines are trimmed of line endings', () {
    final crlf = WordPieceTokenizer.fromVocabLines([
      for (final line in _vocabLines) '$line\r',
    ]);
    expect(crlf.encode('hello').inputIds, [2, 5, 3]);
  });
}
