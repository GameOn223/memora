import 'dart:convert';

final _fence = RegExp(r'```[A-Za-z0-9_-]*[ \t]*\r?\n?([\s\S]*?)```');

/// Pulls the first JSON object out of model text.
///
/// Models asked for JSON sometimes wrap it in a fenced code block or add a
/// sentence around it. This tries the whole text, then fenced blocks, then
/// every balanced `{...}` span in order. Returns null when nothing parses.
Map<String, Object?>? extractJsonObject(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;

  final whole = _decodeObject(trimmed);
  if (whole != null) return whole;

  for (final match in _fence.allMatches(trimmed)) {
    final inner = _decodeObject(match.group(1)!.trim());
    if (inner != null) return inner;
  }

  var start = trimmed.indexOf('{');
  while (start != -1) {
    final end = _closingBrace(trimmed, start);
    if (end != -1) {
      final candidate = _decodeObject(trimmed.substring(start, end + 1));
      if (candidate != null) return candidate;
    }
    start = trimmed.indexOf('{', start + 1);
  }
  return null;
}

Map<String, Object?>? _decodeObject(String text) {
  if (!text.startsWith('{')) return null;
  try {
    final decoded = jsonDecode(text);
    return decoded is Map ? decoded.cast<String, Object?>() : null;
  } on FormatException {
    return null;
  }
}

/// Index of the brace that closes the one at [start], skipping braces inside
/// string literals, or -1.
int _closingBrace(String s, int start) {
  const quote = 0x22, backslash = 0x5C, open = 0x7B, close = 0x7D;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == backslash) {
        escaped = true;
      } else if (c == quote) {
        inString = false;
      }
      continue;
    }
    if (c == quote) {
      inString = true;
    } else if (c == open) {
      depth++;
    } else if (c == close) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}
