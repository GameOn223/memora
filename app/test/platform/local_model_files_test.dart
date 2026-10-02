import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memora/src/platform/local_model_files.dart';
import 'package:memora/src/services/app_services.dart';
import 'package:memora_core/memora_core.dart';
import 'package:memora_providers/memora_providers.dart';

void main() {
  group('gitBlobSha1', () {
    test('matches git hash-object for a known string', () {
      expect(
        gitBlobSha1(utf8.encode('hello world\n')),
        '3b18e512dba79e4c8300dd08aeb37f8e728b8dad',
      );
    });

    test('hashes an empty blob', () {
      expect(gitBlobSha1(const []), 'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391');
    });
  });

  group('PlatformLocalModelFiles', () {
    late Directory temp;

    const modelBytes = 'memora';
    const vocabBytes = 'hello world\n';
    const spec = LocalModelSpec(
      id: 'tiny',
      displayName: 'Tiny model',
      revision: 'abc123',
      dimensions: 4,
      files: [
        LocalModelFile(
          name: 'model.onnx',
          url: 'https://example.test/model.onnx',
          size: 6,
          sha256: '92a3ab086cf61bf313954c3e341c163756e536973f204ef1e732cbf550878111',
        ),
        LocalModelFile(
          name: 'vocab.txt',
          url: 'https://example.test/vocab.txt',
          size: 12,
          gitBlobSha1: '3b18e512dba79e4c8300dd08aeb37f8e728b8dad',
        ),
      ],
    );

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('memora_models_');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    PlatformLocalModelFiles filesWith(Map<String, String> bodies) {
      final client = MockClient((request) async {
        final body = bodies[request.url.path];
        if (body == null) return http.Response('missing', 404);
        return http.Response(body, 200);
      });
      return PlatformLocalModelFiles(
        modelsDir: temp.path,
        catalog: const [spec],
        client: client,
      );
    }

    test('downloads, verifies and reports ready', () async {
      final files = filesWith({
        '/model.onnx': modelBytes,
        '/vocab.txt': vocabBytes,
      });
      expect(await files.state('tiny'), LocalModelState.notDownloaded);

      final progress = await files.download('tiny').toList();

      expect(progress.last, 1.0);
      expect(await files.state('tiny'), LocalModelState.ready);
      final modelPath = await files.path('tiny', 'model.onnx');
      expect(modelPath, isNotNull);
      expect(await File(modelPath!).readAsString(), modelBytes);
      expect(await files.path('tiny', 'unknown.bin'), isNull);
      await files.close();
    });

    test('checksum mismatch deletes the partial file', () async {
      final files = filesWith({
        '/model.onnx': 'MEMORA', // same size, different bytes
        '/vocab.txt': vocabBytes,
      });

      await expectLater(
        files.download('tiny').drain<void>(),
        throwsA(isA<ModelVerificationException>()),
      );

      final dir = Directory('${temp.path}/tiny');
      final leftovers = await dir.list().map((e) => e.path).toList();
      expect(leftovers, isEmpty);
      expect(await files.state('tiny'), LocalModelState.failed);
      expect(await files.path('tiny', 'model.onnx'), isNull);
      await files.close();
    });

    test('wrong size is rejected', () async {
      final files = filesWith({
        '/model.onnx': 'memora and more',
        '/vocab.txt': vocabBytes,
      });

      await expectLater(
        files.download('tiny').drain<void>(),
        throwsA(isA<ModelVerificationException>()),
      );
      expect(File('${temp.path}/tiny/model.onnx.part').existsSync(), isFalse);
      await files.close();
    });

    test('HTTP errors surface as download failures', () async {
      final files = filesWith({'/model.onnx': modelBytes});

      await expectLater(
        files.download('tiny').drain<void>(),
        throwsA(isA<ModelDownloadException>()),
      );
      // The first file was verified and stays for the next attempt.
      expect(File('${temp.path}/tiny/model.onnx').existsSync(), isTrue);
      expect(await files.state('tiny'), LocalModelState.failed);
      await files.close();
    });

    test('remove deletes files and resets state', () async {
      final files = filesWith({
        '/model.onnx': modelBytes,
        '/vocab.txt': vocabBytes,
      });
      await files.download('tiny').drain<void>();

      await files.remove('tiny');

      expect(await files.state('tiny'), LocalModelState.notDownloaded);
      expect(Directory('${temp.path}/tiny').existsSync(), isFalse);
      await files.close();
    });

    test('service watch emits the catalog with state', () async {
      final files = filesWith({
        '/model.onnx': modelBytes,
        '/vocab.txt': vocabBytes,
      });
      final service = PlatformLocalModelService(files);

      final first = await service.watch().first;
      expect(first.single.id, 'tiny');
      expect(first.single.sizeBytes, 18);
      expect(first.single.state, LocalModelState.notDownloaded);

      await service.download('tiny');
      final after = await service.watch().first;
      expect(after.single.state, LocalModelState.ready);
      expect(after.single, isA<LocalModelInfo>());
      await files.close();
    });
  });

  test('the bundled catalog pins bge-small-en-v1.5', () {
    expect(bgeSmallEnV15.dimensions, 384);
    expect(bgeSmallEnV15.files.map((f) => f.name), [
      'model_quantized.onnx',
      'vocab.txt',
    ]);
    for (final file in bgeSmallEnV15.files) {
      expect(file.uri.path, contains(bgeSmallEnV15.revision));
    }
  });
}
