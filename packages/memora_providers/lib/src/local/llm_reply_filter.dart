import 'llm_prompt.dart';

/// Cleans a generated reply while it is still arriving.
///
/// Showing text as the model produces it means the turn markers have to go
/// on the way past, and a marker does not arrive in one piece: `<end_of_` can
/// land in one chunk and `turn>` in the next. So a tail long enough to hold
/// the longest marker is held back, and only text that cannot be the start of
/// one is handed over.
///
/// What [add] and [finish] hand over, joined, is what the whole reply would
/// have been after the markers were stripped and the ends trimmed.
class LocalReplyFilter {
  LocalReplyFilter({this.maxChars = 1 << 20});

  /// Markers that end the reply. Gemma writes this when it has finished, and
  /// a small model sometimes carries on afterwards with another invented
  /// turn, which is not the answer.
  static const endMarkers = [LocalLlmPrompt.endTurn];

  /// Markers to drop wherever they appear.
  static const dropMarkers = [
    LocalLlmPrompt.startModel,
    LocalLlmPrompt.startUser,
    '<start_of_turn>',
  ];

  /// How much is held back, so a marker split across chunks is still seen.
  static final holdback =
      [...endMarkers, ...dropMarkers].map((m) => m.length).reduce(_max) - 1;

  /// Stop after this much text. A model that will not stop is not given the
  /// whole screen.
  final int maxChars;

  final _pending = StringBuffer();
  var _emitted = 0;
  var _anything = false;
  var _done = false;

  /// Whether the reply has ended, by marker or by length.
  bool get done => _done;

  /// Text from [chunk] that is safe to show, which may be empty.
  String add(String chunk) {
    if (_done) return '';
    _pending.write(chunk);
    final text = _pending.toString();

    final end = _firstEnd(text);
    if (end != null) {
      _pending.clear();
      _done = true;
      return _take(text.substring(0, end), last: true);
    }

    // Everything but the tail that cannot be handed over yet. Only a tail
    // already shaping into a marker is held, rather than a fixed fourteen
    // characters, which would make every reply lag by that much.
    //
    // Trailing spaces are held for the same reason: whether they are the
    // middle of the reply or the end of it is not known until more arrives.
    final hold = _markerPrefixAtEnd(text);
    final spaces = _trailingSpaces(text);
    final safe = text.length - (hold > spaces ? hold : spaces);
    if (safe <= 0) return '';
    _pending
      ..clear()
      ..write(text.substring(safe));
    return _take(text.substring(0, safe), last: false);
  }

  /// Whatever is left once the stream has ended.
  String finish() {
    if (_done) return '';
    _done = true;
    final text = _pending.toString();
    _pending.clear();
    final end = _firstEnd(text);
    return _take(end == null ? text : text.substring(0, end), last: true);
  }

  /// Strips the markers, trims the ends that are really ends, and keeps the
  /// running total under [maxChars].
  String _take(String raw, {required bool last}) {
    var text = raw;
    for (final marker in dropMarkers) {
      text = text.replaceAll(marker, '');
    }
    // The start of the reply, and the end once there is no more coming.
    if (!_anything) text = text.trimLeft();
    if (last) text = text.trimRight();
    if (text.isEmpty) return '';

    final room = maxChars - _emitted;
    if (room <= 0) {
      _done = true;
      return '';
    }
    if (text.length >= room) {
      _done = true;
      text = text.substring(0, room);
    }
    _emitted += text.length;
    _anything = true;
    return text;
  }

  /// How many characters at the end of [text] are whitespace, which might
  /// be the end of the reply or might be the middle of it.
  static int _trailingSpaces(String text) {
    var count = 0;
    while (count < text.length &&
        text.codeUnitAt(text.length - 1 - count) <= 0x20) {
      count++;
    }
    return count;
  }

  /// How many characters at the end of [text] are the start of a marker and
  /// so cannot be handed over yet. Zero when the tail is ordinary text.
  static int _markerPrefixAtEnd(String text) {
    final markers = [...endMarkers, ...dropMarkers];
    final most = holdback < text.length ? holdback : text.length;
    for (var length = most; length > 0; length--) {
      final tail = text.substring(text.length - length);
      for (final marker in markers) {
        if (marker.length > length && marker.startsWith(tail)) return length;
      }
    }
    return 0;
  }

  /// Where the reply ends in [text], or null when it does not.
  static int? _firstEnd(String text) {
    int? first;
    for (final marker in endMarkers) {
      final at = text.indexOf(marker);
      if (at != -1 && (first == null || at < first)) first = at;
    }
    return first;
  }

  static int _max(int a, int b) => a > b ? a : b;
}
