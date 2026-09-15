final _token = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// Words that carry no meaning in a search box query.
const _stopwords = <String>{
  'a',
  'all',
  'an',
  'and',
  'are',
  'find',
  'for',
  'from',
  'i',
  'in',
  'is',
  'me',
  'my',
  'of',
  'on',
  'or',
  'saw',
  'show',
  'that',
  'the',
  'this',
  'to',
  'was',
  'what',
  'when',
  'where',
  'which',
  'with',
};

/// Turns user text into a safe FTS5 `MATCH` expression, or null when nothing
/// searchable is left.
///
/// The text is lowercased and split on anything that isn't a letter or digit,
/// so quotes, brackets, colons and operators never reach FTS5. Short tokens
/// and stopwords are dropped. Each remaining token is quoted, tokens of three
/// or more characters match as prefixes (`"bill"*`), and tokens are joined
/// with `OR` so bm25 ranks memories that match more of them higher.
String? ftsMatchExpression(String text) {
  final tokens = <String>{};
  for (final match in _token.allMatches(text.toLowerCase())) {
    final token = match[0]!;
    final length = token.runes.length;
    if (length < 2 || _stopwords.contains(token)) continue;
    tokens.add(token);
  }
  if (tokens.isEmpty) return null;
  return tokens.map((t) => t.runes.length >= 3 ? '"$t"*' : '"$t"').join(' OR ');
}
