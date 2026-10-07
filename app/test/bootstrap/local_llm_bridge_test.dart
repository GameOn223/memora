import 'dart:async';
import 'dart:io';

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

  /// Holds [pickModelFile] open, standing in for a copy still running.
  Completer<void>? hold;

  @override
  Future<bridge.ImportedModel?> pickModelFile() async {
    if (pickError case final error?) throw error;
    await hold?.future;
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

  final List<
    ({String modelId, String url, String fileName, String displayName})
  >
  downloads = [];
  final List<String> cancels = [];

  /// Thrown by [startDownload] when set.
  PlatformException? startError;

  /// What [activeDownload] reports.
  String? active;

  @override
  Future<void> startDownload(
    String modelId,
    String url,
    String fileName,
    String displayName,
  ) async {
    if (startError case final error?) throw error;
    downloads.add((
      modelId: modelId,
      url: url,
      fileName: fileName,
      displayName: displayName,
    ));
  }

  @override
  Future<void> cancelDownload(String relativePath) async =>
      cancels.add(relativePath);

  @override
  Future<String?> activeDownload() async => active;
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
  // A download writes into the files dir, so the bridge needs a real one
  // even in the tests that never download.
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('memora-llm'));
  tearDown(() => tempDir.deleteSync(recursive: true));

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
      files = BridgeLocalLlmFiles(
        settings: settings,
        filesDir: tempDir.path,
        host: host,
      );
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

  group('import progress', () {
    late _FakeImportHost host;
    late StreamController<bridge.ModelImportProgress> reports;
    late BridgeLocalLlmFiles files;
    StreamSubscription<ModelImportEvent>? watching;

    setUp(() {
      host = _FakeImportHost();
      reports = StreamController<bridge.ModelImportProgress>.broadcast();
      files = BridgeLocalLlmFiles(
        settings: _Settings(),
        filesDir: tempDir.path,
        host: host,
        progress: reports.stream,
      );
    });

    tearDown(() async {
      await watching?.cancel();
      watching = null;
      await reports.close();
    });

    /// Starts an import that will not finish until [_FakeImportHost.hold] is
    /// completed, and collects what it emits.
    Future<List<ModelImportEvent>> startHeld() async {
      host.hold = Completer<void>();
      final events = <ModelImportEvent>[];
      watching = files
          .import('gemma-3-1b-it-int4', extensions: const ['.task'])
          .listen(events.add);
      await pumpEventQueue();
      return events;
    }

    test('turns reported bytes into a fraction while the copy runs', () async {
      host.picked = _file('gemma.task', size: 400);
      final events = await startHeld();

      reports.add(
        bridge.ModelImportProgress(copiedBytes: 100, totalBytes: 400),
      );
      reports.add(
        bridge.ModelImportProgress(copiedBytes: 400, totalBytes: 400),
      );
      await pumpEventQueue();

      expect(events.whereType<ModelImportCopying>().map((e) => e.fraction), [
        0.25,
        1.0,
      ]);
      // Still running: the closing event only comes when the copy returns.
      expect(events.whereType<ModelImportDone>(), isEmpty);

      host.hold!.complete();
      await pumpEventQueue();

      expect(events.last, isA<ModelImportDone>());
    });

    test('a source that will not say its size reports no fraction', () async {
      host.picked = _file('gemma.task');
      final events = await startHeld();

      reports.add(
        bridge.ModelImportProgress(copiedBytes: 8 << 20, totalBytes: 0),
      );
      await pumpEventQueue();

      expect(events.whereType<ModelImportCopying>(), isEmpty);

      host.hold!.complete();
      await pumpEventQueue();
      expect(events.single, isA<ModelImportDone>());
    });

    test('a count past the total still reads as finished, not more', () async {
      host.picked = _file('gemma.task', size: 400);
      final events = await startHeld();

      reports.add(
        bridge.ModelImportProgress(copiedBytes: 500, totalBytes: 400),
      );
      await pumpEventQueue();

      expect(events.whereType<ModelImportCopying>().single.fraction, 1.0);
      host.hold!.complete();
      await pumpEventQueue();
    });

    test('stops listening for progress once the import ends', () async {
      host.picked = _file('gemma.task', size: 400);
      final events = await startHeld();
      expect(reports.hasListener, isTrue);

      host.hold!.complete();
      await pumpEventQueue();

      expect(reports.hasListener, isFalse);
      reports.add(
        bridge.ModelImportProgress(copiedBytes: 400, totalBytes: 400),
      );
      await pumpEventQueue();
      expect(events.whereType<ModelImportCopying>(), isEmpty);
    });

    test('a refused file still closes the progress stream', () async {
      host.pickError = PlatformException(code: 'no_space');

      final events = await files
          .import('gemma-3-1b-it-int4', extensions: const ['.task'])
          .toList();

      expect(events.single, isA<ModelImportRefused>());
      expect(reports.hasListener, isFalse);
    });
  });

  group('downloading', () {
    late _FakeImportHost host;
    late _Settings settings;
    late StreamController<bridge.ModelDownloadEvent> events;
    late BridgeLocalLlmFiles files;
    StreamSubscription<ModelImportEvent>? watching;

    setUp(() {
      host = _FakeImportHost();
      settings = _Settings();
      events = StreamController<bridge.ModelDownloadEvent>.broadcast();
      files = BridgeLocalLlmFiles(
        settings: settings,
        filesDir: tempDir.path,
        host: host,
        downloads: events.stream,
      );
    });

    tearDown(() async {
      await watching?.cancel();
      watching = null;
      await events.close();
    });

    bridge.ModelDownloadEvent step(
      int copied,
      int total, {
      bool done = false,
      String? error,
      String modelId = 'gemma-3-1b-it-int4',
    }) => bridge.ModelDownloadEvent(
      modelId: modelId,
      copiedBytes: copied,
      totalBytes: total,
      done: done,
      error: error,
    );

    /// Starts a download and collects what it reports.
    Future<List<ModelImportEvent>> start() async {
      final seen = <ModelImportEvent>[];
      watching = files
          .download('gemma-3-1b-it-int4', token: 'hf_secret')
          .listen(seen.add);
      await pumpEventQueue();
      return seen;
    }

    test('hands the worker the url, file name and display name', () async {
      await start();

      expect(host.downloads, hasLength(1));
      final sent = host.downloads.single;
      expect(sent.modelId, 'gemma-3-1b-it-int4');
      expect(
        sent.url,
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/'
        'gemma3-1b-it-int4.task',
      );
      expect(sent.fileName, 'gemma3-1b-it-int4.task');
      expect(
        sent.displayName,
        'Gemma 3 1B',
        reason: 'the notification calls the model something',
      );
    });

    test('the token is never handed across', () async {
      await start();

      expect(
        host.downloads.single.toString(),
        isNot(contains('hf_secret')),
        reason: 'the worker reads it from the secret store itself',
      );
    });

    test('turns worker bytes into a fraction, then finishes', () async {
      final seen = await start();

      events.add(step(100, 400));
      events.add(step(400, 400));
      await pumpEventQueue();

      expect(seen.whereType<ModelImportCopying>().map((e) => e.fraction), [
        0.25,
        1.0,
      ]);

      events.add(step(400, 400, done: true));
      await pumpEventQueue();

      final done = seen.last as ModelImportDone;
      expect(done.model.modelId, 'gemma-3-1b-it-int4');
      expect(done.model.relativePath, 'models/imported/gemma3-1b-it-int4.task');
      expect(done.model.sizeBytes, 400);
      expect(settings.values[BridgeLocalLlmFiles.settingsKey], {
        'gemma-3-1b-it-int4': 'models/imported/gemma3-1b-it-int4.task',
      });
    });

    test('events for another model are ignored', () async {
      final seen = await start();

      events.add(step(100, 400, modelId: 'gemma-3n-e2b-it-int4'));
      events.add(step(400, 400, done: true, modelId: 'something-else'));
      await pumpEventQueue();

      expect(seen, isEmpty);
      expect(settings.values, isEmpty);
    });

    test('a worker error becomes the refusal it stands for', () async {
      for (final (code, expected) in [
        ('no_token', ModelImportRefusal.tokenRejected),
        ('unauthorized', ModelImportRefusal.tokenRejected),
        ('forbidden', ModelImportRefusal.licenceNotAccepted),
        ('no_space', ModelImportRefusal.notEnoughStorage),
        ('unsupported_model', ModelImportRefusal.wrongFileType),
        ('short_download', ModelImportRefusal.downloadFailed),
        ('anything else', ModelImportRefusal.downloadFailed),
      ]) {
        expect(
          BridgeLocalLlmFiles.refusalForCode(code),
          expected,
          reason: code,
        );
      }
    });

    test('an error event ends the stream and records nothing', () async {
      final seen = await start();

      events.add(step(0, 0, done: true, error: 'forbidden'));
      await pumpEventQueue();

      expect(
        (seen.single as ModelImportRefused).reason,
        ModelImportRefusal.licenceNotAccepted,
      );
      expect(settings.values, isEmpty);
    });

    test('a worker that refuses to start says why', () async {
      host.startError = PlatformException(code: 'unsupported_model');

      final seen = await files
          .download('gemma-3-1b-it-int4', token: 'hf_x')
          .toList();

      expect(
        (seen.single as ModelImportRefused).reason,
        ModelImportRefusal.wrongFileType,
      );
    });

    test(
      'a model that is not in the catalog never reaches the worker',
      () async {
        final seen = await files.download('made-up', token: 'hf_x').toList();

        expect(
          (seen.single as ModelImportRefused).reason,
          ModelImportRefusal.unreadable,
        );
        expect(host.downloads, isEmpty);
      },
    );

    test('watching follows a download without starting one', () async {
      final seen = <ModelImportEvent>[];
      watching = files.watchDownload('gemma-3-1b-it-int4').listen(seen.add);
      await pumpEventQueue();

      expect(
        host.downloads,
        isEmpty,
        reason: 'opening settings mid-download must not restart it',
      );

      events.add(step(200, 400));
      await pumpEventQueue();
      expect(seen.whereType<ModelImportCopying>().single.fraction, 0.5);
    });

    test('leaving the screen does not cancel the download', () async {
      await start();
      await watching!.cancel();
      watching = null;

      expect(host.cancels, isEmpty);
    });

    test('cancel and active go through to the worker', () async {
      host.active = 'gemma-3-1b-it-int4';
      expect(await files.activeDownload(), 'gemma-3-1b-it-int4');

      await files.cancelDownload();
      expect(host.cancels, hasLength(1));
    });

    test('a download that finished unseen is still installed', () async {
      // Three gigabytes takes minutes and Memora is in the background for
      // most of them, so the worker renames the file with nothing listening
      // and no record is ever written. The file has to speak for itself or
      // the model looks like it vanished and has to be fetched again.
      host.files.add(_file('gemma-3n-E2B-it-int4.task', size: 3 << 30));

      final installed = await files.installed();

      expect(installed.single.modelId, 'gemma-3n-e2b-it-int4');
      expect(
        installed.single.relativePath,
        'models/imported/gemma-3n-E2B-it-int4.task',
      );
      expect(installed.single.sizeBytes, 3 << 30);
      expect(settings.values, isNotEmpty, reason: 'and it is written down');
    });

    test('an unseen download can be removed again', () async {
      host.files.add(_file('gemma-3n-E2B-it-int4.task', size: 3 << 30));

      await files.remove('gemma-3n-e2b-it-int4');

      expect(host.deletes, ['models/imported/gemma-3n-E2B-it-int4.task']);
      expect(await files.installed(), isEmpty);
    });

    test('an imported file keeps its own name and its record', () async {
      // Not a catalog name, so only the record says what it is.
      host.files.add(_file('my-copy.task', size: 550));
      await settings.write(BridgeLocalLlmFiles.settingsKey, {
        'gemma-3-1b-it-int4': 'models/imported/my-copy.task',
      });

      final installed = await files.installed();

      expect(installed.single.modelId, 'gemma-3-1b-it-int4');
      expect(installed.single.relativePath, 'models/imported/my-copy.task');
    });

    test('a file that is neither is ignored', () async {
      host.files.add(_file('something-else.task', size: 100));

      expect(await files.installed(), isEmpty);
    });

    test('downloading over an earlier file removes the old one', () async {
      await settings.write(BridgeLocalLlmFiles.settingsKey, {
        'gemma-3-1b-it-int4': 'models/imported/old.task',
      });
      await start();

      events.add(step(16, 16, done: true));
      await pumpEventQueue();

      expect(host.deletes, ['models/imported/old.task']);
    });
  });
}
