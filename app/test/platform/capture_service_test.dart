import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/platform/messages.g.dart';
import 'package:memora/src/platform/platform_capture_service.dart';
import 'package:memora_core/memora_core.dart';

import 'fakes.dart';

void main() {
  test('files tile and share captures under their own source', () async {
    final host = _FakeCaptureHost([
      _inbox('originals/1.png', 'tile'),
      _inbox('originals/2.jpg', 'share'),
      _inbox('originals/3.png', 'tile'),
    ]);
    final ingestor = FakeIngestor();
    final scheduler = FakeScheduler();
    final service = PlatformCaptureService(
      ingestor: ingestor,
      scheduler: scheduler,
      host: host,
    );

    final added = await service.ingestInbox();

    expect(added, 3);
    expect(ingestor.calls, hasLength(2));
    final tile = ingestor.calls.firstWhere(
      (c) => c.source == MemorySource.tile,
    );
    expect(tile.files.map((f) => f.imagePath), [
      'originals/1.png',
      'originals/3.png',
    ]);
    expect(tile.files.first.takenAt.millisecondsSinceEpoch, 42);
    final share = ingestor.calls.firstWhere(
      (c) => c.source == MemorySource.share,
    );
    expect(share.files.single.imagePath, 'originals/2.jpg');
    expect(scheduler.refreshes, 1);
  });

  test('an empty inbox does nothing', () async {
    final scheduler = FakeScheduler();
    final service = PlatformCaptureService(
      ingestor: FakeIngestor(),
      scheduler: scheduler,
      host: _FakeCaptureHost([]),
    );

    expect(await service.ingestInbox(), 0);
    expect(scheduler.refreshes, 0);
  });

  test('overlapping calls share one drain', () async {
    final host = _FakeCaptureHost([_inbox('originals/1.png', 'tile')]);
    final service = PlatformCaptureService(
      ingestor: FakeIngestor(),
      scheduler: FakeScheduler(),
      host: host,
    );

    final results = await Future.wait([
      service.ingestInbox(),
      service.ingestInbox(),
    ]);

    expect(results, [1, 1]);
    expect(host.drains, 1);
  });

  test('reports setup status', () async {
    final service = PlatformCaptureService(
      ingestor: FakeIngestor(),
      scheduler: FakeScheduler(),
      host: _FakeCaptureHost([]),
    );

    final setup = await service.setup();

    expect(setup.accessibilitySupported, isTrue);
    expect(setup.accessibilityEnabled, isFalse);
    expect(setup.canRequestTile, isTrue);
    expect(setup.notificationsAllowed, isFalse);
  });

  test('unknown inbox sources count as tile captures', () {
    expect(memorySourceFromInbox('share'), MemorySource.share);
    expect(memorySourceFromInbox('tile'), MemorySource.tile);
    expect(memorySourceFromInbox('something-new'), MemorySource.tile);
  });
}

InboxItem _inbox(String path, String source) => InboxItem(
  relativePath: path,
  source: source,
  capturedAtMillis: 42,
  sha256: path,
  mimeType: 'image/png',
  width: 10,
  height: 20,
  byteSize: 30,
);

class _FakeCaptureHost extends CaptureHostApi {
  _FakeCaptureHost(this.items);

  final List<InboxItem> items;
  var drains = 0;

  @override
  Future<CaptureStatus> status() async => CaptureStatus(
    accessibilitySupported: true,
    accessibilityEnabled: false,
    canRequestTile: true,
    notificationsAllowed: false,
  );

  @override
  Future<List<InboxItem>> drainInbox() async {
    drains++;
    await Future<void>.delayed(Duration.zero);
    final result = List<InboxItem>.of(items);
    items.clear();
    return result;
  }
}
