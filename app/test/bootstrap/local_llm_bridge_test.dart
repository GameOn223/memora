import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/bootstrap/local_llm_bridge.dart';
import 'package:memora/src/platform/messages.g.dart' as bridge;
import 'package:memora_core/memora_core.dart';

class _FakeLlmHost extends bridge.LlmHostApi {
  final List<({String path, bool vision, int maxTokens})> loads = [];
  final List<({String prompt, List<Uint8List> images, int maxTokens})> starts =
      [];
  final List<int> cancels = [];
  int unloads = 0;
  int nextRequestId = 7;
  String? path;

  /// Thrown by [load] when set.
  PlatformException? loadError;

  /// Thrown by [startGeneration] when set.
  Object? startError;

  bridge.DeviceMemory reported = bridge.DeviceMemory(
    totalBytes: 8,
    availableBytes: 5,
    lowRamDevice: false,
  );

  @override
  Future<void> load(
    String relativeModelPath,
    bool vision,
    int maxTokens,
  ) async {
    if (loadError case final error?) throw error;
    loads.add((path: relativeModelPath, vision: vision, maxTokens: maxTokens));
    path = relativeModelPath;
  }

  @override
  Future<bool> isLoaded() async => path != null;

  @override
  Future<String?> loadedModelPath() async => path;

  @override
  Future<void> unload() async {
    unloads++;
    path = null;
  }

  @override
  Future<int> startGeneration(
    String prompt,
    List<Uint8List> images,
    int maxTokens,
  ) async {
    if (startError case final error?) throw error;
    starts.add((prompt: prompt, images: images, maxTokens: maxTokens));
    return nextRequestId;
  }

  @override
  Future<void> cancelGeneration(int requestId) async => cancels.add(requestId);

  @override
  Future<bridge.DeviceMemory> deviceMemory() async => reported;
}

class _FakeImportHost extends bridge.ModelImportHostApi {
  final List<bridge.ImportedModel> files = [];
  final List<String> deletes = [];

  /// What the picker returns next. Null means the user cancelled.
  bridge.ImportedModel? picked;

  /// Thrown by [pickModelFile] when set.
  PlatformException? pickError;

  @override
  Future<bridge.ImportedModel?> pickModelFile() async {
    if (pickError case final error?) throw error;
    final model = picked;
    if (model != null) files.add(model);
    return model;
  }

  @override
  Future<void> deleteModel(String relativePath) async {
    deletes.add(relativePath);
    files.removeWhere((file) => file.relativePath == relativePath);
  }

  @override
  Future<List<bridge.ImportedModel>> listModels() async => [...files];
}

class _Settings implements SettingsStore {
  final Map<String, Object?> values = {};

  @override
  Future<Object?> read(String key) async => values[key];

  @override
  Future<void> write(String key, Object? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

bridge.ImportedModel _file(String name, {int size = 1024}) =>
    bridge.ImportedModel(
      relativePath: 'models/imported/$name',
      fileName: name,
      byteSize: size,
    );

void main() {
  group('the runtime', () {
    late _FakeLlmHost host;
    late StreamController<bridge.LlmChunk> chunks;
    late BridgeLocalLlmRuntime runtime;

    setUp(() {
      host = _FakeLlmHost();
      chunks = StreamController<bridge.LlmChunk>.broadcast();
      runtime = BridgeLocalLlmRuntime(host: host, chunks: chunks.stream);
    });

    tearDown(() => chunks.close());

    bridge.LlmChunk chunk(
      String text, {
      bool done = false,
      String? error,
      int requestId = 7,
    }) => bridge.LlmChunk(
      requestId: requestId,
      text: text,
      done: done,
      error: error,
    );

    test('passes a load through and remembers the path', () async {
      await runtime.load('models/imported/gemma.task', vision: true);

      expect(host.loads.single.path, 'models/imported/gemma.task');
      expect(host.loads.single.vision, isTrue);
      expect(host.loads.single.maxTokens, 4096);
      expect(await runtime.isLoaded(), isTrue);
      expect(await runtime.loadedModelPath(), 'models/imported/gemma.task');

      await runtime.unload();
      expect(host.unloads, 1);
      expect(await runtime.isLoaded(), isFalse);
    });

    test('a phone that cannot hold the model is a settings problem', () async {
      host.loadError = PlatformException(
        code: 'model_too_large',
        message: 'That model needs more memory than this phone has.',
      );

      await expectLater(
        runtime.load('models/imported/big.task', vision: false),
        throwsA(
          isA<AiConfigurationException>().having(
            (e) => e.message,
            'message',
            contains('more memory than this phone has'),
          ),
        ),
      );
    });

    test('running out of free memory is worth retrying', () async {
      host.loadError = PlatformException(code: 'not_enough_memory');

      await expectLater(
        runtime.load('models/imported/big.task', vision: false),
        throwsA(isA<AiTransientException>()),
      );
    });

    test('keeps only the pieces of its own request', () async {
      final collected = <String>[];
      final reading = runtime
          .generate(
            'prompt',
            images: [
              Uint8List.fromList([1]),
            ],
          )
          .listen(collected.add);
      await pumpEventQueue();

      chunks
        ..add(chunk('wrong', requestId: 99))
        ..add(chunk('Your '))
        ..add(chunk('bill.'))
        ..add(chunk('', done: true));
      await pumpEventQueue();
      await reading.cancel();

      expect(collected, ['Your ', 'bill.']);
      expect(host.starts.single.prompt, 'prompt');
      expect(host.starts.single.images.single, [1]);
    });

    test('a piece that arrives before the id is not lost', () async {
      final collected = <String>[];
      // No pump, so the first chunk lands while startGeneration is still in
      // flight, which is what happens on a fast model.
      final reading = runtime.generate('prompt').listen(collected.add);
      chunks
        ..add(chunk('Fou'))
        ..add(chunk('nd it.', done: true));
      await pumpEventQueue();
      await reading.cancel();

      expect(collected.join(), 'Found it.');
    });

    test('cancelling the stream stops the generation', () async {
      final reading = runtime.generate('prompt').listen((_) {});
      await pumpEventQueue();
      chunks.add(chunk('half'));
      await pumpEventQueue();

      await reading.cancel();

      expect(host.cancels, [7]);
    });

    test('an error on a chunk ends the stream', () async {
      final stream = runtime.generate('prompt');
      final failure = expectLater(
        stream,
        emitsInOrder([
          'half',
          emitsError(isA<AiTransientException>()),
          emitsDone,
        ]),
      );
      await pumpEventQueue();
      chunks
        ..add(chunk('half'))
        ..add(chunk('', done: true, error: 'the engine was killed'));
      await failure;
    });

    test('a refused start ends the stream', () async {
      host.startError = PlatformException(code: 'busy', message: 'Busy.');

      await expectLater(
        runtime.generate('prompt'),
        emitsInOrder([emitsError(isA<AiTransientException>()), emitsDone]),
      );
    });

    test('reports what the phone has', () async {
      host.reported = bridge.DeviceMemory(
        totalBytes: 3 * 1024 * 1024 * 1024,
        availableBytes: 900 * 1024 * 1024,
        lowRamDevice: true,
      );

      final memory = await runtime.memory();

      expect(memory.totalBytes, 3 * 1024 * 1024 * 1024);
      expect(memory.availableBytes, 900 * 1024 * 1024);
      expect(memory.lowRamDevice, isTrue);
    });
  });

  group('imported files', () {
    late _FakeImportHost host;
    late _Settings settings;
    late BridgeLocalLlmFiles files;

    setUp(() {
      host = _FakeImportHost();
      settings = _Settings();
      files = BridgeLocalLlmFiles(settings: settings, host: host);
    });

    test('records the catalog id the user was importing', () async {
      host.picked = _file('gemma3-1b-it-int4.task', size: 550);

      final events = await files
          .import('gemma-3-1b-it-int4', extensions: const ['.task'])
          .toList();

      final done = events.single as ModelImportDone;
      expect(done.model.modelId, 'gemma-3-1b-it-int4');
      expect(done.model.relativePath, 'models/imported/gemma3-1b-it-int4.task');
      expect(done.model.sizeBytes, 550);
      expect(settings.values[BridgeLocalLlmFiles.settingsKey], {
        'gemma-3-1b-it-int4': 'models/imported/gemma3-1b-it-int4.task',
      });

      final installed = await files.installed();
      expect(installed.single.modelId, 'gemma-3-1b-it-int4');
    });

    test('a closed picker changes nothing', () async {
      final events = await files
          .import('gemma-3-1b-it-int4', extensions: const ['.task'])
          .toList();

      expect(events.single, isA<ModelImportCancelled>());
      expect(settings.values, isEmpty);
      expect(await files.installed(), isEmpty);
    });

    test('passes on why the picker refused a file', () async {
      host.pickError = PlatformException(code: 'unsupported_model');
      expect(
        ((await files
                    .import('gemma-3-1b-it-int4', extensions: const ['.task'])
                    .toList())
                .single
            as ModelImportRefused),
        isA<ModelImportRefused>().having(
          (e) => e.reason,
          'reason',
          ModelImportRefusal.wrongFileType,
        ),
      );

      host.pickError = PlatformException(code: 'no_space');
      expect(
        BridgeLocalLlmFiles.refusalFor('no_space'),
        ModelImportRefusal.notEnoughStorage,
      );
      expect(
        BridgeLocalLlmFiles.refusalFor('copy_failed'),
        ModelImportRefusal.unreadable,
      );
    });

    test('importing again replaces the earlier file', () async {
      host.picked = _file('first.task');
      await files
          .import('gemma-3-1b-it-int4', extensions: const ['.task'])
          .toList();
      host.picked = _file('second.task');
      await files
          .import('gemma-3-1b-it-int4', extensions: const ['.task'])
          .toList();

      expect(host.deletes, ['models/imported/first.task']);
      expect(host.files.map((f) => f.fileName), ['second.task']);
      final installed = await files.installed();
      expect(installed.single.relativePath, 'models/imported/second.task');
    });

    test('a file removed from outside drops out of the record', () async {
      host.picked = _file('gemma.task');
      await files
          .import('gemma-3-1b-it-int4', extensions: const ['.task'])
          .toList();

      host.files.clear();

      expect(await files.installed(), isEmpty);
      expect(settings.values, isEmpty);
    });

    test('removing deletes the file and the record', () async {
      host.picked = _file('gemma.task');
      await files
          .import('gemma-3-1b-it-int4', extensions: const ['.task'])
          .toList();

      await files.remove('gemma-3-1b-it-int4');

      expect(host.deletes, ['models/imported/gemma.task']);
      expect(settings.values, isEmpty);
      expect(await files.installed(), isEmpty);
    });

    test('removing something that was never imported does nothing', () async {
      await files.remove('gemma-3n-e2b-it-int4');
      expect(host.deletes, isEmpty);
    });
  });
}
