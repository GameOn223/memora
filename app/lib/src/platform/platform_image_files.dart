import 'dart:io';
import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

import 'app_paths.dart';
import 'messages.g.dart';

/// [ImageFiles] for app-private storage. Reads and deletes go through
/// `dart:io`; thumbnails are drawn natively because Android decodes HEIC and
/// large JPEGs faster and with less memory than Dart can.
class PlatformImageFiles implements ImageFiles {
  PlatformImageFiles({required this.filesDir, GalleryHostApi? gallery})
    : _gallery = gallery ?? GalleryHostApi();

  /// Absolute path of the app files directory.
  final String filesDir;
  final GalleryHostApi _gallery;

  /// Looks up the files directory once. [absolutePath] is synchronous, so the
  /// directory has to be known before this object exists.
  static Future<PlatformImageFiles> open({
    FilesHostApi? files,
    GalleryHostApi? gallery,
  }) async {
    final dir = await (files ?? FilesHostApi()).filesDir();
    return PlatformImageFiles(filesDir: dir, gallery: gallery);
  }

  @override
  String absolutePath(String relativePath) =>
      resolveInside(filesDir, relativePath);

  @override
  Future<Uint8List> readBytes(String relativePath) =>
      File(absolutePath(relativePath)).readAsBytes();

  @override
  Future<String> createThumbnail(String sourcePath, {int maxEdge = 512}) {
    // Validates the path on this side too, so a bad value fails fast.
    absolutePath(sourcePath);
    return _gallery.createThumbnail(sourcePath, maxEdge);
  }

  @override
  Future<void> delete(List<String> relativePaths) async {
    for (final path in relativePaths) {
      final file = File(absolutePath(path));
      try {
        await file.delete();
      } on PathNotFoundException {
        // Already gone, which is what the caller wanted.
      }
    }
  }
}
