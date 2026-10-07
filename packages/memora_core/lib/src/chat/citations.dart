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

/// Strips citation markers from an answer that is still arriving.
///
/// A marker sits in the middle of the text and does not arrive in one piece,
/// so a tail that could still become one is held back. Flashing up half a
/// marker on screen for an instant would read as a bug.
///
/// The spacing cleanup is lighter than [stripCitations], which works on the
/// whole answer at once. That does not matter: the saved answer arrives
/// afterwards and is the one kept.
class CitationStreamFilter {
  /// Longest a marker can be, from  to  with a 64 character id.
  static const _longest = 70;

  final _pending = StringBuffer();

  /// Text from [chunk] with every complete marker gone, which may be empty.
  String add(String chunk) {
    _pending.write(chunk);
    final text = _pending.toString();
    final held = _heldFrom(text);
    _pending
      ..clear()
      ..write(text.substring(held));
    return held == 0 ? '' : _clean(text.substring(0, held));
  }

  /// Whatever is left once the answer has ended.
  String finish() {
    final text = _pending.toString();
    _pending.clear();
    return _clean(text);
  }

  /// Where the tail that cannot be handed over yet begins.
  static int _heldFrom(String text) {
    final open = text.lastIndexOf('[[');
    if (open != -1 &&
        !text.substring(open).contains(']]') &&
        text.length - open <= _longest) {
      return open;
    }
    // A single bracket at the end might be the start of one.
    if (text.endsWith('[')) return text.length - 1;
    return text.length;
  }

  static String _clean(String text) =>
      text.replaceAll(_marker, '').replaceAll(_spaceBefore, '');
}
