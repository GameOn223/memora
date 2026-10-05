/// Gemini accepts a subset of OpenAPI schema for `responseSchema` and
/// function parameters.
library;

const _supportedKeys = {
  'type',
  'format',
  'title',
  'description',
  'nullable',
  'enum',
  'maxItems',
  'minItems',
  'properties',
  'required',
  'minProperties',
  'maxProperties',
  'minLength',
  'maxLength',
  'pattern',
  'example',
  'anyOf',
  'propertyOrdering',
  'default',
  'items',
  'minimum',
  'maximum',
};

/// Converts a JSON schema to the form Gemini accepts.
///
/// A type list such as `["string", "null"]` becomes `type: string` with
/// `nullable: true`, and a list of several types becomes `anyOf`. Keys
/// Gemini doesn't know, such as `additionalProperties` and `const`, are
/// dropped.
Map<String, Object?> geminiSchema(Map<String, Object?> schema) =>
    _convert(schema);

Map<String, Object?> _convert(Map<Object?, Object?> node) {
  final out = <String, Object?>{};
  for (final entry in node.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is! String || !_supportedKeys.contains(key)) continue;
    switch (key) {
      case 'type' when value is List:
        final types = value.whereType<String>().toList();
        final nonNull = types.where((t) => t != 'null').toList();
        if (types.length != nonNull.length) out['nullable'] = true;
        if (nonNull.length == 1) {
          out['type'] = nonNull.single;
        } else if (nonNull.length > 1) {
          out['anyOf'] = [
            for (final t in nonNull) {'type': t},
          ];
        }
      case 'properties' when value is Map:
        out[key] = {
          for (final p in value.entries)
            if (p.value is Map) '${p.key}': _convert(p.value! as Map),
        };
      case 'items' when value is Map:
        out[key] = _convert(value);
      case 'anyOf' when value is List:
        out[key] = [
          for (final option in value)
            if (option is Map) _convert(option),
        ];
      default:
        out[key] = value;
    }
  }
  return out;
}
