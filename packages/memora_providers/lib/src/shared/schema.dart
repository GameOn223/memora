/// Adjustments to JSON schemas for providers with stricter rules.
library;

/// Returns a copy of [schema] with `additionalProperties: false` on every
/// object, as OpenAI structured output expects.
Map<String, Object?> closedSchema(Map<String, Object?> schema) =>
    _close(schema)! as Map<String, Object?>;

Object? _close(Object? node) {
  if (node is List) return [for (final item in node) _close(item)];
  if (node is! Map) return node;

  final out = <String, Object?>{};
  for (final entry in node.entries) {
    final key = entry.key as String;
    final value = entry.value;
    out[key] = switch (key) {
      'properties' || r'$defs' || 'definitions' when value is Map => {
        for (final p in value.entries) p.key as String: _close(p.value),
      },
      'items' || 'anyOf' || 'oneOf' || 'allOf' => _close(value),
      _ => value,
    };
  }
  final type = node['type'];
  final isObject =
      type == 'object' || (type is List && type.contains('object'));
  if (isObject) out.putIfAbsent('additionalProperties', () => false);
  return out;
}
