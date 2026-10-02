import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

import '../fakes/fake_stores.dart';

ImportedFile _file(String name, {String? sha}) => ImportedFile(
  imagePath: 'originals/$name.png',
  sha256: sha ?? 'sha-$name',
  mimeType: 'image/png',
  width: 1080,
  height: 2400,
  byteSize: 4200,
  takenAt: DateTime(2026, 8, 12, 9, 30),
);

void main() {
  late FakeMemora db;
  late FakeImageFiles images;
  late FixedClock clock;
  late DefaultMemoryIngestor ingestor;

  setUp(() {
    db = FakeMemora();
    images = FakeImageFiles();
    clock = FixedClock(DateTime(2026, 9, 15, 10));
    ingestor = DefaultMemoryIngestor(
      memories: db,
      images: images,
      clock: clock,
      ids: SequentialIds(),
    );
  });

  test('files new images as captured memories with thumbnails', () async {
    final report = await ingestor.ingest([
      _file('a'),
      _file('b'),
    ], MemorySource.share);

    expect(report.addedIds, ['id-1', 'id-2']);
    expect(report.duplicateCount, 0);
    expect(report.duplicatePaths, isEmpty);

    final memory = (await db.getMemory('id-1'))!;
    expect(memory.status, ProcessingStatus.captured);
    expect(memory.source, MemorySource.share);
    expect(memory.imagePath, 'originals/a.png');
    expect(memory.sha256, 'sha-a');
    expect(memory.takenAt, DateTime(2026, 8, 12, 9, 30));
    expect(memory.addedAt, clock.current);
    expect(memory.thumbnailPath, 'thumbnails/a.webp');
    expect((await db.getMemory('id-2'))!.thumbnailPath, 'thumbnails/b.webp');
    expect(images.deleted, isEmpty);
  });

  test('skips duplicates and deletes their copied files', () async {
    await ingestor.ingest([_file('a')], MemorySource.gallery);

    final report = await ingestor.ingest([
      _file('a-again', sha: 'sha-a'),
      _file('c'),
      _file('c-twice', sha: 'sha-c'),
    ], MemorySource.gallery);

    expect(report.addedIds, hasLength(1));
    expect(report.duplicateCount, 2);
    expect(report.duplicatePaths, [
      'originals/a-again.png',
      'originals/c-twice.png',
    ], reason: 'the caller has to be able to remove the wasted copies');
    expect(images.deleted, ['originals/a-again.png', 'originals/c-twice.png']);
    expect(images.thumbnailsCreated, [
      'thumbnails/a.webp',
      'thumbnails/c.webp',
    ]);
  });

  test('a thumbnail failure does not fail the import', () async {
    images.failingThumbnails.add('originals/b.png');

    final report = await ingestor.ingest([
      _file('a'),
      _file('b'),
    ], MemorySource.tile);

    expect(report.addedIds, hasLength(2));
    expect((await db.getMemory(report.addedIds[1]))!.thumbnailPath, isNull);
    expect((await db.getMemory(report.addedIds[0]))!.thumbnailPath, isNotNull);
  });

  test('backfill creates missing thumbnails and counts successes', () async {
    images.failingThumbnails.addAll(['originals/a.png', 'originals/b.png']);
    await ingestor.ingest([_file('a'), _file('b')], MemorySource.gallery);

    images.failingThumbnails.remove('originals/a.png');
    expect(await ingestor.backfillThumbnails(), 1);
    expect((await db.getMemory('id-1'))!.thumbnailPath, 'thumbnails/a.webp');

    images.failingThumbnails.clear();
    expect(await ingestor.backfillThumbnails(), 1);
    expect(await ingestor.backfillThumbnails(), 0);
  });

  test('backfill stops even when every thumbnail keeps failing', () async {
    for (var i = 0; i < 60; i++) {
      images.failingThumbnails.add('originals/f$i.png');
    }
    await ingestor.ingest([
      for (var i = 0; i < 60; i++) _file('f$i'),
    ], MemorySource.gallery);

    expect(await ingestor.backfillThumbnails(), 0);
  });
}
