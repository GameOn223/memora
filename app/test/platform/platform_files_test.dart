import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/platform/app_paths.dart';
import 'package:memora/src/platform/messages.g.dart';
import 'package:memora/src/platform/platform_image_files.dart';
import 'package:memora/src/platform/platform_secret_store.dart';

void main() {
  group('resolveInside', () {
    test('joins a relative path', () {
      expect(
        resolveInside('/data/files', 'originals/a.png'),
        '/data/files/originals/a.png',
      );
      expect(
        resolveInside('/data/files/', './thumbs/a.webp'),
        '/data/files/thumbs/a.webp',
      );
    });

    test('refuses escapes and absolute paths', () {
      expect(
        () => resolveInside('/data/files', '../databases/memora.db'),
        throwsArgumentError,
      );
      expect(
        () => resolveInside('/data/files', '/etc/hosts'),
        throwsArgumentError,
      );
      expect(() => resolveInside('/data/files', ''), throwsArgumentError);
    });
  });

  group('PlatformImageFiles', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('memora_files_');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('reads, deletes and ignores missing files', () async {
      final files = await PlatformImageFiles.open(
        files: _FakeFilesHost(temp.path),
        gallery: _FakeGalleryHost(),
      );
      await Directory('${temp.path}/originals').create();
      await File('${temp.path}/originals/a.png').writeAsBytes([1, 2, 3]);

      expect(await files.readBytes('originals/a.png'), [1, 2, 3]);
      await files.delete(['originals/a.png', 'originals/gone.png']);
      expect(File('${temp.path}/originals/a.png').existsSync(), isFalse);
    });

    test('draws thumbnails natively and refuses unsafe paths', () async {
      final gallery = _FakeGalleryHost();
      final files = PlatformImageFiles(filesDir: temp.path, gallery: gallery);

      expect(
        await files.createThumbnail('originals/a.png', maxEdge: 256),
        'thumbnails/a.webp',
      );
      expect(gallery.thumbnailCalls, ['originals/a.png@256']);
      expect(
        () => files.createThumbnail('../secrets.xml'),
        throwsArgumentError,
      );
    });
  });

  test('secret store forwards to the host', () async {
    final host = _FakeSecretHost();
    final store = PlatformSecretStore(host: host);

    await store.write('provider.groq.api_key', 'gsk_1');
    expect(await store.read('provider.groq.api_key'), 'gsk_1');
    expect(await store.keys(), ['provider.groq.api_key']);
    await store.delete('provider.groq.api_key');
    expect(await store.read('provider.groq.api_key'), isNull);
  });
}

class _FakeFilesHost extends FilesHostApi {
  _FakeFilesHost(this.dir);

  final String dir;

  @override
  Future<String> filesDir() async => dir;
}

class _FakeGalleryHost extends GalleryHostApi {
  final thumbnailCalls = <String>[];

  @override
  Future<String> createThumbnail(String relativeSourcePath, int maxEdge) async {
    thumbnailCalls.add('$relativeSourcePath@$maxEdge');
    return 'thumbnails/a.webp';
  }
}

class _FakeSecretHost extends SecretHostApi {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<List<String>> keys() async => values.keys.toList();
}
