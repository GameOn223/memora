import 'dart:typed_data';

import '../ports/platform.dart';
import '../text/normalize.dart';

/// BERT uncased WordPiece tokenization, matching what sentence embedding
/// models such as bge-small-en-v1.5 were trained with.
///
/// Runs in Dart so it can be tested on the host. The ONNX model itself runs
/// natively. See docs/architecture.md, section 7.5.
class WordPieceTokenizer {
  WordPieceTokenizer(Map<String, int> vocab, {this.maxLength = 512})
    : assert(maxLength >= 2, 'maxLength must leave room for [CLS] and [SEP]'),
      _vocab = Map.unmodifiable(vocab),
      _clsId = _required(vocab, cls),
      _sepId = _required(vocab, sep),
      _unkId = _required(vocab, unk),
      _padId = vocab[pad] ?? 0;

  /// Builds a tokenizer from the lines of a `vocab.txt` file, where each
  /// line's index is its token id.
  factory WordPieceTokenizer.fromVocabLines(
    List<String> lines, {
    int maxLength = 512,
  }) {
    final vocab = <String, int>{};
    for (var i = 0; i < lines.length; i++) {
      final token = lines[i].trimRight();
      if (token.isEmpty) continue;
      vocab.putIfAbsent(token, () => i);
    }
    return WordPieceTokenizer(vocab, maxLength: maxLength);
  }

  static const cls = '[CLS]';
  static const sep = '[SEP]';
  static const unk = '[UNK]';
  static const pad = '[PAD]';

  /// Words longer than this become `[UNK]`, as in the reference tokenizer.
  static const maxCharsPerWord = 100;

  /// Longest sequence produced, including `[CLS]` and `[SEP]`.
  final int maxLength;

  final Map<String, int> _vocab;
  final int _clsId;
  final int _sepId;
  final int _unkId;
  final int _padId;

  static int _required(Map<String, int> vocab, String token) {
    final id = vocab[token];
    if (id == null) {
      throw ArgumentError.value(token, 'vocab', 'Missing special token');
    }
    return id;
  }

  /// Word pieces for [text] without special tokens or truncation.
  List<String> tokenize(String text) => [
    for (final word in _basicTokens(text)) ..._wordPieces(word),
  ];

  EncodedText encode(String text) {
    final ids = _ids(text);
    return EncodedText(
      inputIds: Int64List.fromList(ids),
      attentionMask: Int64List(ids.length)..fillRange(0, ids.length, 1),
      tokenTypeIds: Int64List(ids.length),
    );
  }

  /// Encodes several texts and pads every row with `[PAD]` to the longest.
  List<EncodedText> encodeBatch(List<String> texts) {
    final rows = [for (final text in texts) _ids(text)];
    final width = rows.fold(0, (w, row) => row.length > w ? row.length : w);
    return [
      for (final row in rows)
        EncodedText(
          inputIds: Int64List(width)
            ..setAll(0, row)
            ..fillRange(row.length, width, _padId),
          attentionMask: Int64List(width)..fillRange(0, row.length, 1),
          tokenTypeIds: Int64List(width),
        ),
    ];
  }

  List<int> _ids(String text) {
    final pieces = tokenize(text);
    final room = maxLength - 2;
    final kept = pieces.length > room ? pieces.sublist(0, room) : pieces;
    return [_clsId, for (final piece in kept) _vocab[piece] ?? _unkId, _sepId];
  }

  static final _control = RegExp(r'[\p{Cc}\p{Cf}]', unicode: true);
  static final _spaceSeparator = RegExp(r'\p{Zs}', unicode: true);
  static final _punctuation = RegExp(r'\p{P}', unicode: true);
  static final _nonspacingMark = RegExp(r'\p{Mn}', unicode: true);

  /// Cleans, lowercases, strips accents and splits on whitespace and
  /// punctuation, like BERT's basic tokenizer with lowercasing on.
  List<String> _basicTokens(String text) {
    final words = <String>[];
    final current = StringBuffer();

    void flush() {
      if (current.isNotEmpty) {
        words.add(current.toString());
        current.clear();
      }
    }

    final folded = stripLatinAccents(text.toLowerCase());
    for (final rune in folded.runes) {
      if (rune == 0 || rune == 0xfffd) continue;
      final char = String.fromCharCode(rune);
      if (_isWhitespace(rune, char)) {
        flush();
        continue;
      }
      if (_control.hasMatch(char)) continue;
      if (_nonspacingMark.hasMatch(char)) continue;
      if (_isCjk(rune) || _isPunctuation(rune, char)) {
        flush();
        words.add(char);
        continue;
      }
      current.write(char);
    }
    flush();
    return words;
  }

  bool _isWhitespace(int rune, String char) =>
      rune == 0x20 ||
      rune == 0x09 ||
      rune == 0x0a ||
      rune == 0x0d ||
      _spaceSeparator.hasMatch(char);

  bool _isPunctuation(int rune, String char) =>
      (rune >= 33 && rune <= 47) ||
      (rune >= 58 && rune <= 64) ||
      (rune >= 91 && rune <= 96) ||
      (rune >= 123 && rune <= 126) ||
      _punctuation.hasMatch(char);

  bool _isCjk(int rune) =>
      (rune >= 0x4e00 && rune <= 0x9fff) ||
      (rune >= 0x3400 && rune <= 0x4dbf) ||
      (rune >= 0x20000 && rune <= 0x2a6df) ||
      (rune >= 0x2a700 && rune <= 0x2b73f) ||
      (rune >= 0x2b740 && rune <= 0x2b81f) ||
      (rune >= 0x2b820 && rune <= 0x2ceaf) ||
      (rune >= 0xf900 && rune <= 0xfaff) ||
      (rune >= 0x2f800 && rune <= 0x2fa1f);

  /// Greedy longest-match-first split of one word into vocabulary pieces.
  List<String> _wordPieces(String word) {
    final chars = word.runes.toList();
    if (chars.length > maxCharsPerWord) return const [unk];
    final pieces = <String>[];
    var start = 0;
    while (start < chars.length) {
      String? match;
      var end = chars.length;
      while (start < end) {
        final piece = String.fromCharCodes(chars, start, end);
        final candidate = start > 0 ? '##$piece' : piece;
        if (_vocab.containsKey(candidate)) {
          match = candidate;
          break;
        }
        end--;
      }
      if (match == null) return const [unk];
      pieces.add(match);
      start = end;
    }
    return pieces;
  }
}
