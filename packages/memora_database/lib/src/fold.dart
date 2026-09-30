/// Latin letters that Unicode builds from a base letter plus a mark, grouped
/// under the base letter they fold to. Letters that carry a stroke or a bar
/// instead of a mark (ø, ł, đ, ħ, ŧ) and ligatures (æ, œ, ß) are left alone,
/// the same way Unicode decomposition leaves them.
const _accented = <String, String>{
  'a': 'àáâãäåāăą',
  'c': 'çćĉċč',
  'd': 'ď',
  'e': 'èéêëēĕėęě',
  'g': 'ĝğġģ',
  'h': 'ĥ',
  'i': 'ìíîïĩīĭį',
  'j': 'ĵ',
  'k': 'ķ',
  'l': 'ĺļľ',
  'n': 'ñńņň',
  'o': 'òóôõöōŏő',
  'r': 'ŕŗř',
  's': 'śŝşš',
  't': 'ţť',
  'u': 'ùúûüũūŭůűų',
  'w': 'ŵ',
  'y': 'ýÿŷ',
  'z': 'źżž',
};

final _folded = <int, String>{
  for (final MapEntry(key: base, value: accents) in _accented.entries)
    for (final rune in accents.runes) rune: base,
};

final _whitespace = RegExp(r'\s+');

/// Folds text for entity matching: lowercase, accents off Latin letters,
/// runs of whitespace collapsed, ends trimmed.
///
/// `entities.normalized_value` is written in this shape by whoever stores the
/// facts, so filter values have to be folded the same way. Keep this in step
/// with core's `foldForMatch`, and with the `remove_diacritics 2` setting on
/// the FTS index, which folds the same Latin letters.
String foldForMatch(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    // Combining marks, for text that is already decomposed.
    if (rune >= 0x0300 && rune <= 0x036F) continue;
    buffer.write(_folded[rune] ?? String.fromCharCode(rune));
  }
  return buffer.toString().replaceAll(_whitespace, ' ').trim();
}
