import 'package:memora_core/memora_core.dart';

import '../services/app_services.dart';
import 'messages.g.dart';

/// [CaptureService] for the Quick Settings tile and the share sheet.
///
/// Kotlin writes captures and shared images into `files/inbox/` because it
/// can't safely write to the database. [ingestInbox] turns them into rows.
class PlatformCaptureService implements CaptureService {
  PlatformCaptureService({
    required this._ingestor,
    required this._scheduler,
    this._images,
    CaptureHostApi? host,
  }) : _host = host ?? CaptureHostApi();

  final MemoryIngestor _ingestor;
  final QueueScheduler _scheduler;
  final ImageFiles? _images;
  final CaptureHostApi _host;

  Future<int>? _ingesting;

  @override
  Future<CaptureSetup> setup() async {
    final status = await _host.status();
    return CaptureSetup(
      accessibilitySupported: status.accessibilitySupported,
      accessibilityEnabled: status.accessibilityEnabled,
      canRequestTile: status.canRequestTile,
      notificationsAllowed: status.notificationsAllowed,
    );
  }

  @override
  Future<void> openAccessibilitySettings() => _host.openAccessibilitySettings();

  @override
  Future<bool> requestAddTile() => _host.requestAddTile();

  @override
  Future<bool> requestNotificationPermission() =>
      _host.requestNotificationPermission();

  @override
  Future<int> ingestInbox() {
    // Resume events can arrive in bursts. One drain at a time is enough.
    return _ingesting ??= _ingest().whenComplete(() => _ingesting = null);
  }

  Future<int> _ingest() async {
    final items = await _host.drainInbox();
    if (items.isEmpty) return 0;
    final bySource = <MemorySource, List<InboxItem>>{};
    for (final item in items) {
      bySource
          .putIfAbsent(memorySourceFromInbox(item.source), () => [])
          .add(item);
    }
    var added = 0;
    // Only what is now in the database is acknowledged. Anything left
    // unconfirmed is offered again by the next drain, and the second pass
    // is dropped as a duplicate of the same image.
    final filed = <String>[];
    try {
      for (final entry in bySource.entries) {
        final report = await _ingestor.ingest([
          for (final item in entry.value) importedFileFromInbox(item),
        ], entry.key);
        added += report.addedIds.length;
        filed.addAll([for (final item in entry.value) item.id]);
        // A replayed capture is copied again, and the copy is what the
        // store skipped. Nothing points at it, so it goes.
        if (report.duplicatePaths.isNotEmpty) {
          await _images?.delete(report.duplicatePaths);
        }
      }
    } finally {
      if (filed.isNotEmpty) await _host.confirmInbox(filed);
    }
    if (added > 0) await _scheduler.refresh();
    return added;
  }
}

MemorySource memorySourceFromInbox(String source) =>
    source == MemorySource.share.dbValue
    ? MemorySource.share
    : MemorySource.tile;

ImportedFile importedFileFromInbox(InboxItem item) => ImportedFile(
  imagePath: item.relativePath,
  sha256: item.sha256,
  mimeType: item.mimeType,
  width: item.width,
  height: item.height,
  byteSize: item.byteSize,
  takenAt: DateTime.fromMillisecondsSinceEpoch(item.capturedAtMillis),
);
