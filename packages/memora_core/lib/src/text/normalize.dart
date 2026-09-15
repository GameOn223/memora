/// Case and accent folding shared by matching, search and tokenization.
library;

/// Latin letters whose accents come off under canonical decomposition (NFD),
/// keyed by the base letter they fold to.
const _canonicalFolds = {
  'a': 'àáâãäåāăąǎǟǡǻȁȃȧạảấầẩẫậắằẳẵặ',
  'æ': 'ǽ',
  'c': 'çćĉċč',
  'd': 'ď',
  'e': 'èéêëēĕėęěȅȇȩẹẻẽếềểễệ',
  'g': 'ĝğġģǧ',
  'h': 'ĥ',
  'i': 'ìíîïĩīĭįǐȉȋỉị',
  'j': 'ĵ',
  'k': 'ķǩ',
  'l': 'ĺļľ',
  'n': 'ñńņňǹ',
  'o': 'òóôõöōŏőǒǫȍȏȯọỏốồổỗộớờởỡợơ',
  'r': 'ŕŗřȑȓ',
  's': 'śŝşšș',
  't': 'ţťț',
  'u': 'ùúûüũūŭůűųưǔǖǘǚǜȕȗụủứừửữự',
  'w': 'ŵ',
  'y': 'ýÿŷỳỵỷỹ',
  'z': 'źżž',
};

/// Latin letters with no decomposition that still read as a plain letter
/// when someone types a search.
const _extraFolds = {
  'æ': 'ae',
  'ß': 'ss',
  'đ': 'd',
  'ð': 'd',
  'ħ': 'h',
  'ı': 'i',
  'ŀ': 'l',
  'ł': 'l',
  'ŉ': 'n',
  'ø': 'o',
  'œ': 'oe',
  'ŧ': 't',
  'þ': 'th',
};

final Map<int, String> _canonical = {
  for (final entry in _canonicalFolds.entries)
    for (final rune in entry.value.runes) rune: entry.key,
};

final Map<int, String> _extra = {
  for (final entry in _extraFolds.entries) entry.key.runes.single: entry.value,
};

bool _isCombiningMark(int rune) => rune >= 0x0300 && rune <= 0x036f;

/// Removes accents from lowercase Latin letters the way Unicode NFD followed
/// by dropping combining marks would. Letters without a decomposition, such
/// as `ø` or `ß`, are kept.
String stripLatinAccents(String input) => _fold(input, extra: false);

String _fold(String input, {required bool extra}) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    if (_isCombiningMark(rune)) continue;
    var replacement = _canonical[rune];
    if (replacement != null && extra) {
      replacement = _extra[replacement.runes.first] ?? replacement;
    }
    if (replacement == null && extra) replacement = _extra[rune];
    if (replacement != null) {
      out.write(replacement);
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

final _whitespace = RegExp(r'\s+');

/// Folds text for entity matching: lowercase, Latin accents removed,
/// whitespace collapsed and trimmed. `Café  Coffee` becomes `cafe coffee`.
String foldForMatch(String input) =>
    _fold(input.toLowerCase(), extra: true).replaceAll(_whitespace, ' ').trim();

/// Words too common to help a search.
const searchStopwords = <String>{
  'a',
  'an',
  'the',
  'of',
  'for',
  'to',
  'in',
  'on',
  'my',
  'me',
  'show',
  'find',
  'all',
  'and',
  'or',
  'that',
  'this',
  'with',
  'from',
  'i',
  'saw',
  'was',
  'is',
  'are',
  'what',
  'which',
  'where',
  'when',
};

final _wordPattern = RegExp(r'[\p{L}\p{M}\p{N}]+', unicode: true);

/// Splits free text into folded search tokens: letters and digits only, at
/// least two characters, stopwords removed. Order is kept and repeats are
/// dropped.
List<String> searchTokens(String text) {
  final seen = <String>{};
  return [
    for (final match in _wordPattern.allMatches(foldForMatch(text)))
      if (match[0]!.length >= 2 &&
          !searchStopwords.contains(match[0]) &&
          seen.add(match[0]!))
        match[0]!,
  ];
}
