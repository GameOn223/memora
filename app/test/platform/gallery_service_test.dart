import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/platform/messages.g.dart';
import 'package:memora/src/platform/platform_gallery_service.dart';
import 'package:memora/src/services/app_services.dart';
import 'package:memora_core/memora_core.dart';

import 'fakes.dart';

void main() {
  test('copies in batches, files as gallery memories and nudges the '
      'scheduler once', () async {
    final host = _FakeGalleryHost();
    final ingestor = FakeIngestor(duplicatesPerBatch: 1);
    final scheduler = FakeScheduler();
    final service = PlatformGalleryService(
      ingestor: ingestor,
      scheduler: scheduler,
      host: host,
      copyBatchSize: 2,
    );

    final result = await service.addToMemora([
      'content://a',
      'content://b',
      'content://c',
      'content://bad',
    ]);

    expect(host.copyCalls, [
      ['content://a', 'content://b'],
      ['content://c', 'content://bad'],
    ]);
    expect(ingestor.calls.map((c) => c.source), [
      MemorySource.gallery,
      MemorySource.gallery,
    ]);
    expect(ingestor.calls.first.files.first.imagePath, 'originals/a.png');
    expect(
      ingestor.calls.first.files.first.takenAt.millisecondsSinceEpoch,
      1000,
    );
    expect(result.added, 1);
    expect(result.duplicates, 2);
    expect(result.failed, 1);
    expect(scheduler.refreshes, 1);
  });

  test('nothing added means no reschedule', () async {
    final scheduler = FakeScheduler();
    final service = PlatformGalleryService(
      ingestor: FakeIngestor(duplicatesPerBatch: 1),
      scheduler: scheduler,
      host: _FakeGalleryHost(),
    );

    final result = await service.addToMemora(['content://a']);

    expect(result.added, 0);
    expect(result.duplicates, 1);
    expect(scheduler.refreshes, 0);
  });

  test('deletes copies when filing fails', () async {
    final images = FakeImageFiles();
    final service = PlatformGalleryService(
      ingestor: FakeIngestor(fail: true),
      scheduler: FakeScheduler(),
      images: images,
      host: _FakeGalleryHost(),
    );

    await expectLater(
      service.addToMemora(['content://a']),
      throwsA(isA<StateError>()),
    );
    expect(images.deleted, ['originals/a.png']);
  });

  test('lists device images newest first as given', () async {
    final service = PlatformGalleryService(
      ingestor: FakeIngestor(),
      scheduler: FakeScheduler(),
      host: _FakeGalleryHost(),
    );

    final page = await service.list(offset: 0, limit: 2);

    expect(page.hasMore, isTrue);
    expect(page.images.single.uri, 'content://media/1');
    expect(page.images.single.takenAt.millisecondsSinceEpoch, 5000);
    expect(page.images.single.mimeType, 'image/jpeg');
  });

  test('maps permission states', () {
    expect(galleryAccessFrom(GalleryPermission.granted), GalleryAccess.full);
    expect(galleryAccessFrom(GalleryPermission.partial), GalleryAccess.partial);
    expect(galleryAccessFrom(GalleryPermission.denied), GalleryAccess.denied);
    expect(
      galleryAccessFrom(GalleryPermission.permanentlyDenied),
      GalleryAccess.permanentlyDenied,
    );
  });
}

class _FakeGalleryHost extends GalleryHostApi {
  final copyCalls = <List<String>>[];

  @override
  Future<GalleryPage> listImages(int offset, int limit) async => GalleryPage(
    images: [
      GalleryImage(
        uri: 'content://media/1',
        takenAtMillis: 5000,
        width: 1080,
        height: 2400,
        byteSize: 1234,
        mimeType: 'image/jpeg',
      ),
    ],
    hasMore: true,
  );

  @override
  Future<CopyResult> copyToAppStorage(List<String> uris) async {
    copyCalls.add(uris);
    return CopyResult(
      copied: [
        for (final uri in uris)
          if (!uri.endsWith('bad'))
            CopiedImage(
              sourceUri: uri,
              relativePath: 'originals/${uri.split('//').last}.png',
              sha256: uri,
              mimeType: 'image/png',
              width: 1,
              height: 1,
              byteSize: 1,
              takenAtMillis: 1000,
            ),
      ],
      failed: [
        for (final uri in uris)
          if (uri.endsWith('bad')) CopyFailure(sourceUri: uri, message: 'no'),
      ],
    );
  }
}
