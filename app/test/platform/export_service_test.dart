import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/platform/messages.g.dart';
import 'package:memora/src/platform/platform_export_service.dart';
import 'package:memora/src/services/app_services.dart';
import 'package:memora_core/memora_core.dart';

import 'fakes.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('memora_export_');
    await Directory('${temp.path}/files/originals').create(recursive: true);
    await File('${temp.path}/files/originals/a.png')
        .writeAsBytes(List<int>.filled(16, 7));
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  PlatformExportService serviceWith(_FakeFilesHost host) {
    final memory = _memory();
    return PlatformExportService(
      builder: ExportBuilder(
        memories: _FakeMemoryStore(memory),
        conversations: _FakeConversationStore(),
        vectors: _FakeVectorStore(),
        clock: FixedClock(_exportedAt),
        appVersion: '0.1.0',
      ),
      images: _LocalImageFiles('${temp.path}/files'),
      cacheDirectory: temp,
      clock: FixedClock(_exportedAt),
      files: host,
    );
  }

  test('writes a zip with the documented entries and saves it', () async {
    final host = _FakeFilesHost(saved: true, copyTo: '${temp.path}/out.zip');
    final service = serviceWith(host);
    final progress = <ExportProgress>[];

    final saved = await service.exportAll(onProgress: progress.add);

    expect(saved, isTrue);
    expect(host.suggestedName, 'memora-export-2026-09-15.zip');
    expect(host.mimeType, 'application/zip');
    expect(progress.map((p) => p.done), [0, 1]);
    expect(progress.last.total, 1);

    final archive = ZipDecoder().decodeBytes(
      await File('${temp.path}/out.zip').readAsBytes(),
    );
    expect(archive.files.map((f) => f.name), [
      'manifest.json',
      'memories.jsonl',
      'conversations.jsonl',
      'images/m1.png',
    ]);

    final manifest = jsonDecode(
      utf8.decode(archive.findFile('manifest.json')!.content as List<int>),
    ) as Map<String, Object?>;
    expect(manifest['format'], 'memora-export');
    expect(manifest['format_version'], 1);
    expect((manifest['counts']! as Map)['memories'], 1);

    final line = utf8
        .decode(archive.findFile('memories.jsonl')!.content as List<int>)
        .trim();
    final record = jsonDecode(line) as Map<String, Object?>;
    expect(record['id'], 'm1');
    expect(record['image_file'], 'images/m1.png');
    expect(record['source_path'], 'originals/a.png');
    expect(record['summary'], 'Reliance electricity bill');

    // Nothing is left behind in the cache.
    final leftovers = await temp
        .list()
        .where((e) => e.path.contains('export-'))
        .toList();
    expect(leftovers, isEmpty);
  });

  test('a cancelled save reports false and cleans up', () async {
    final host = _FakeFilesHost(saved: false);
    final service = serviceWith(host);

    expect(await service.exportAll(), isFalse);
    final leftovers = await temp
        .list()
        .where((e) => e.path.contains('export-'))
        .toList();
    expect(leftovers, isEmpty);
  });

  test('names the file after the export day', () {
    expect(
      PlatformExportService.fileNameFor(DateTime(2026, 1, 5, 23, 30)),
      'memora-export-2026-01-05.zip',
    );
  });
}

final _exportedAt = DateTime(2026, 9, 15, 10, 30);

Memory _memory() => Memory(
  id: 'm1',
  imagePath: 'originals/a.png',
  source: MemorySource.gallery,
  sha256: 'abc',
  mimeType: 'image/png',
  width: 1080,
  height: 2400,
  byteSize: 16,
  takenAt: DateTime.utc(2026, 8, 14),
  addedAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
  status: ProcessingStatus.ready,
  summary: 'Reliance electricity bill',
  category: 'utility_bill',
);

class _LocalImageFiles implements ImageFiles {
  _LocalImageFiles(this.root);

  final String root;

  @override
  String absolutePath(String relativePath) => '$root/$relativePath';

  @override
  Future<Uint8List> readBytes(String relativePath) =>
      File(absolutePath(relativePath)).readAsBytes();

  @override
  Future<String> createThumbnail(String sourcePath, {int maxEdge = 512}) =>
      throw UnimplementedError();

  @override
  Future<void> delete(List<String> relativePaths) async {}
}

class _FakeFilesHost extends FilesHostApi {
  _FakeFilesHost({required this.saved, this.copyTo});

  final bool saved;
  final String? copyTo;
  String? suggestedName;
  String? mimeType;

  @override
  Future<String> filesDir() async => '/files';

  @override
  Future<bool> saveToUserLocation(
    String absoluteSourcePath,
    String suggestedName,
    String mimeType,
  ) async {
    this.suggestedName = suggestedName;
    this.mimeType = mimeType;
    if (!saved) return false;
    final target = copyTo;
    if (target != null) await File(absoluteSourcePath).copy(target);
    return true;
  }
}

class _FakeMemoryStore implements MemoryStore {
  _FakeMemoryStore(this.memory);

  final Memory memory;

  @override
  Future<StorageStats> storageStats() async =>
      StorageStats(memoryCount: 1, imageBytes: memory.byteSize);

  @override
  Future<List<Memory>> listMemories(MemoryListQuery query) async =>
      query.offset == 0 ? [memory] : const [];

  @override
  Future<MemoryDetails?> getDetails(String id) async => MemoryDetails(
    memory: memory,
    entities: const [
      StoredEntity(
        type: 'company',
        value: 'Reliance',
        normalizedValue: 'reliance',
      ),
    ],
    attributes: const [
      StoredAttribute(
        type: 'amount',
        value: '₹1,842',
        valueNum: 1842,
        currency: 'INR',
        label: 'total',
      ),
    ],
    keywords: const ['reliance', 'bill'],
    processing: const [],
    conversationCount: 0,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeConversationStore implements ConversationStore {
  @override
  Future<List<Conversation>> listConversations() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVectorStore implements VectorStore {
  @override
  Future<List<String>> missingFor(
    EmbeddingModelInfo model, {
    int limit = 100,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
