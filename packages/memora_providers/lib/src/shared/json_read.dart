/// Small readers for loosely typed provider JSON.
library;

import 'dart:convert';

Map<String, Object?>? asObject(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

List<Object?> asList(Object? value) =>
    value is List ? value.cast<Object?>() : const [];

String? asString(Object? value) => value is String ? value : null;

/// Tool call arguments arrive as JSON text or as an object. Anything that
/// isn't a JSON object becomes an empty map, so a sloppy model produces a
/// tool validation error instead of a crash.
Map<String, Object?> decodeArguments(Object? raw) {
  if (raw is Map) return raw.cast<String, Object?>();
  if (raw is! String || raw.trim().isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? decoded.cast<String, Object?>() : {};
  } on FormatException {
    return {};
  }
}

/// Decodes JSON text for a tool result, falling back to the raw string.
Object? decodeToolContent(String content) {
  try {
    return jsonDecode(content);
  } on FormatException {
    return content;
  }
}
