import 'dart:io';

/// Resolves a path relative to the app files directory and refuses anything
/// that would land outside it, such as `../databases/memora.db`.
String resolveInside(String root, String relativePath) {
  if (relativePath.isEmpty) {
    throw ArgumentError.value(relativePath, 'relativePath', 'Empty path');
  }
  final normalized = relativePath.replaceAll('\\', '/');
  if (normalized.startsWith('/')) {
    throw ArgumentError.value(relativePath, 'relativePath', 'Must be relative');
  }
  final segments = <String>[];
  for (final segment in normalized.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'Must stay inside the app files directory',
      );
    }
    segments.add(segment);
  }
  if (segments.isEmpty) {
    throw ArgumentError.value(relativePath, 'relativePath', 'Empty path');
  }
  final base = root.endsWith(Platform.pathSeparator) || root.endsWith('/')
      ? root.substring(0, root.length - 1)
      : root;
  return [base, ...segments].join('/');
}
