/// Small helpers for reading loosely typed JSON, mostly model output.
library;

String? readString(Map<String, Object?> json, String key) {
  final value = json[key];
  return switch (value) {
    final String s => s,
    final num n => n.toString(),
    _ => null,
  };
}

num? readNum(Map<String, Object?> json, String key) {
  final value = json[key];
  return switch (value) {
    final num n => n,
    final String s => num.tryParse(s.replaceAll(',', '').trim()),
    _ => null,
  };
}

bool? readBool(Map<String, Object?> json, String key) {
  final value = json[key];
  return switch (value) {
    final bool b => b,
    'true' => true,
    'false' => false,
    _ => null,
  };
}

List<Object?> readList(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is List ? value.cast<Object?>() : const [];
}

/// Returns only the entries of a list that are JSON objects.
List<Map<String, Object?>> readObjects(Map<String, Object?> json, String key) {
  return [
    for (final item in readList(json, key))
      if (item is Map) item.cast<String, Object?>(),
  ];
}

/// Turns free-form labels into snake_case keys: "Due Date" becomes `due_date`.
String normalizeKey(String input) {
  final cleaned = input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return cleaned.isEmpty ? 'other' : cleaned;
}
