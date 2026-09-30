/// Citation markers the chat model writes, such as `[[m:9f2c]]`.
library;

final _marker = RegExp(r'\[\[m:([^\]\s]{1,64})\]\]');
final _spaceBefore = RegExp(r'[ \t]+(?=[.,;:!?)\]])');
final _runs = RegExp('[ \t]{2,}');

/// Memory ids cited in [text], in the order they first appear.
List<String> parseCitations(String text) {
  final seen = <String>{};
  return [
    for (final m in _marker.allMatches(text))
      if (seen.add(m[1]!)) m[1]!,
  ];
}

/// Removes the markers and the spacing they leave behind, so the text reads
/// as if they were never there.
String stripCitations(String text) {
  return text
      .replaceAll(_marker, '')
      .replaceAll(_spaceBefore, '')
      .replaceAll(_runs, ' ')
      .split('\n')
      .map((line) => line.trim())
      .join('\n')
      .trim();
}
