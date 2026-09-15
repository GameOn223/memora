import '../model/memory.dart';
import '../ports/platform.dart';
import '../ports/stores.dart';
import '../services/contracts.dart';

/// Files copied images as `captured` memories and makes their thumbnails.
///
/// Never waits on AI. Thumbnails are best effort: a failure leaves the
/// memory without one, and [backfillThumbnails] tries again later.
class DefaultMemoryIngestor implements MemoryIngestor {
  DefaultMemoryIngestor({
    required this._memories,
    required this._images,
    required this._clock,
    required this._ids,
  });

  final MemoryStore _memories;
  final ImageFiles _images;
  final Clock _clock;
  final IdGenerator _ids;

  @override
  Future<IngestReport> ingest(
    List<ImportedFile> files,
    MemorySource source,
  ) async {
    final rows = [
      for (final file in files)
        NewMemory(
          id: _ids.next(),
          imagePath: file.imagePath,
          source: source,
          sha256: file.sha256,
          mimeType: file.mimeType,
          width: file.width,
          height: file.height,
          byteSize: file.byteSize,
          takenAt: file.takenAt,
        ),
    ];
    final outcome = await _memories.insertCaptured(rows, _clock.now());

    if (outcome.duplicates.isNotEmpty) {
      try {
        await _images.delete([for (final d in outcome.duplicates) d.imagePath]);
      } on Exception {
        // Leftover copies only waste space; the import itself succeeded.
      }
    }

    final byId = {for (final row in rows) row.id: row};
    for (final id in outcome.insertedIds) {
      final row = byId[id];
      if (row != null) await _thumbnail(id, row.imagePath);
    }

    return IngestReport(
      addedIds: outcome.insertedIds,
      duplicateCount: outcome.duplicates.length,
    );
  }

  @override
  Future<int> backfillThumbnails() async {
    final attempted = <String>{};
    var created = 0;
    while (true) {
      final batch = await _memories.missingThumbnails(
        limit: attempted.length + 50,
      );
      final fresh = batch.where((m) => attempted.add(m.id)).toList();
      if (fresh.isEmpty) return created;
      for (final memory in fresh) {
        if (await _thumbnail(memory.id, memory.imagePath)) created++;
      }
    }
  }

  Future<bool> _thumbnail(String id, String imagePath) async {
    try {
      final path = await _images.createThumbnail(imagePath);
      await _memories.setThumbnail(id, path, _clock.now());
      return true;
    } on Exception {
      return false;
    }
  }
}
