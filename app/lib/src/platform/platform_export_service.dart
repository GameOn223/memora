import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:memora_core/memora_core.dart';
import 'package:path_provider/path_provider.dart';

import '../services/app_services.dart';
import 'messages.g.dart';

/// Writes "Export all memories" as a zip and hands it to the system save
/// dialog. See docs/export-format.md for what goes inside.
class PlatformExportService implements ExportService {
  PlatformExportService({
    required this._builder,
    required this._images,
    this._cacheDirectory,
    this._clock = const SystemClock(),
    FilesHostApi? files,
  }) : _files = files ?? FilesHostApi();

  static const mimeType = 'application/zip';

  final ExportBuilder _builder;
  final ImageFiles _images;
  final Directory? _cacheDirectory;
  final Clock _clock;
  final FilesHostApi _files;

  @override
  Future<bool> exportAll({
    void Function(ExportProgress progress)? onProgress,
  }) async {
    final cache = _cacheDirectory ?? await getTemporaryDirectory();
    final work = Directory(
      '${cache.path}/export-${_clock.now().millisecondsSinceEpoch}',
    );
    await work.create(recursive: true);
    try {
      final manifest = await _builder.manifest();
      onProgress?.call(ExportProgress(done: 0, total: manifest.memoryCount));

      final imagePaths = <String, String>{};
      final memories = File('${work.path}/memories.jsonl');
      final sink = memories.openWrite();
      var done = 0;
      try {
        await for (final record in _builder.memories()) {
          sink.writeln(jsonEncode(record.toJson()));
          imagePaths[record.imageFile] = record.sourcePath;
          done++;
          onProgress?.call(
            ExportProgress(done: done, total: manifest.memoryCount),
          );
        }
      } finally {
        await sink.close();
      }

      final conversations = File('${work.path}/conversations.jsonl');
      final conversationSink = conversations.openWrite();
      try {
        await for (final conversation in _builder.conversations()) {
          conversationSink.writeln(jsonEncode(conversation));
        }
      } finally {
        await conversationSink.close();
      }

      final manifestFile = File('${work.path}/manifest.json');
      await manifestFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      );

      final name = fileNameFor(manifest.exportedAt);
      final zipPath = '${work.path}/$name';
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      try {
        await encoder.addFile(manifestFile, 'manifest.json');
        await encoder.addFile(memories, 'memories.jsonl');
        await encoder.addFile(conversations, 'conversations.jsonl');
        for (final entry in imagePaths.entries) {
          final file = File(_images.absolutePath(entry.value));
          // A memory deleted while the export runs is simply left out.
          if (!await file.exists()) continue;
          await encoder.addFile(file, entry.key);
        }
      } finally {
        await encoder.close();
      }

      return await _files.saveToUserLocation(zipPath, name, mimeType);
    } finally {
      // The zip lives in the cache only until the user picks a location.
      if (await work.exists()) await work.delete(recursive: true);
    }
  }

  /// `memora-export-2026-09-15.zip`, in local time.
  static String fileNameFor(DateTime exportedAt) {
    final local = exportedAt.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return 'memora-export-${local.year}-$month-$day.zip';
  }
}
