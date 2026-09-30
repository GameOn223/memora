import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

class FakeFileException implements Exception {
  const FakeFileException(this.message);

  final String message;

  @override
  String toString() => 'FakeFileException: $message';
}

/// In-memory [ImageFiles]. Every path reads as a few bytes unless listed in
/// [missing]. Thumbnails fail for paths in [failingThumbnails].
class FakeImageFiles implements ImageFiles {
  final Set<String> missing = {};
  final Set<String> failingThumbnails = {};
  final List<String> deleted = [];
  final List<String> thumbnailsCreated = [];
  final List<String> reads = [];

  @override
  String absolutePath(String relativePath) => '/data/files/$relativePath';

  @override
  Future<String> createThumbnail(String sourcePath, {int maxEdge = 512}) async {
    if (failingThumbnails.contains(sourcePath)) {
      throw FakeFileException('cannot decode $sourcePath');
    }
    final name = sourcePath.split('/').last.split('.').first;
    final path = 'thumbnails/$name.webp';
    thumbnailsCreated.add(path);
    return path;
  }

  @override
  Future<void> delete(List<String> relativePaths) async {
    deleted.addAll(relativePaths);
  }

  @override
  Future<Uint8List> readBytes(String relativePath) async {
    reads.add(relativePath);
    if (missing.contains(relativePath)) {
      throw FakeFileException('missing $relativePath');
    }
    return Uint8List.fromList([1, 2, 3]);
  }
}
