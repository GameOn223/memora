import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

import '../services/app_services.dart';
import 'messages.g.dart';

/// [GalleryService] on top of MediaStore through [GalleryHostApi].
class PlatformGalleryService implements GalleryService {
  PlatformGalleryService({
    required this._ingestor,
    required this._scheduler,
    this._images,
    GalleryHostApi? host,
    this.copyBatchSize = 50,
  }) : _host = host ?? GalleryHostApi();

  final MemoryIngestor _ingestor;
  final QueueScheduler _scheduler;
  final ImageFiles? _images;
  final GalleryHostApi _host;

  /// Images copied and filed per round trip. Smaller batches mean less work
  /// is lost if the app is killed halfway through a large selection.
  final int copyBatchSize;

  @override
  Future<GalleryAccess> access() async =>
      galleryAccessFrom(await _host.permissionState());

  @override
  Future<GalleryAccess> requestAccess() async =>
      galleryAccessFrom(await _host.requestPermission());

  @override
  Future<void> openAppSettings() => _host.openAppSettings();

  @override
  Future<DeviceImagePage> list({
    required int offset,
    required int limit,
  }) async {
    final page = await _host.listImages(offset, limit);
    return DeviceImagePage(
      images: [for (final image in page.images) deviceImageFrom(image)],
      hasMore: page.hasMore,
    );
  }

  @override
  Future<Uint8List> thumbnail(String uri, {int size = 256}) =>
      _host.thumbnail(uri, size);

  @override
  Future<List<String>> pickWithSystemPicker({int maxItems = 100}) =>
      _host.pickWithSystemPicker(maxItems);

  @override
  Future<AddImagesResult> addToMemora(List<String> uris) async {
    var added = 0;
    var duplicates = 0;
    var failed = 0;
    for (var start = 0; start < uris.length; start += copyBatchSize) {
      final end = start + copyBatchSize < uris.length
          ? start + copyBatchSize
          : uris.length;
      final result = await _host.copyToAppStorage(uris.sublist(start, end));
      failed += result.failed.length;
      if (result.copied.isEmpty) continue;
      final files = [for (final c in result.copied) importedFileFrom(c)];
      try {
        final report = await _ingestor.ingest(files, MemorySource.gallery);
        added += report.addedIds.length;
        duplicates += report.duplicateCount;
      } catch (_) {
        // The rows were not written, so the copies would be orphans.
        await _images?.delete([for (final f in files) f.imagePath]);
        rethrow;
      }
    }
    if (added > 0) await _scheduler.refresh();
    return AddImagesResult(
      added: added,
      duplicates: duplicates,
      failed: failed,
    );
  }
}

GalleryAccess galleryAccessFrom(GalleryPermission permission) =>
    switch (permission) {
      GalleryPermission.granted => GalleryAccess.full,
      GalleryPermission.partial => GalleryAccess.partial,
      GalleryPermission.denied => GalleryAccess.denied,
      GalleryPermission.permanentlyDenied => GalleryAccess.permanentlyDenied,
    };

DeviceImage deviceImageFrom(GalleryImage image) => DeviceImage(
  uri: image.uri,
  takenAt: DateTime.fromMillisecondsSinceEpoch(image.takenAtMillis),
  width: image.width,
  height: image.height,
  byteSize: image.byteSize,
  mimeType: image.mimeType,
);

ImportedFile importedFileFrom(CopiedImage copied) => ImportedFile(
  imagePath: copied.relativePath,
  sha256: copied.sha256,
  mimeType: copied.mimeType,
  width: copied.width,
  height: copied.height,
  byteSize: copied.byteSize,
  takenAt: DateTime.fromMillisecondsSinceEpoch(copied.takenAtMillis),
);
