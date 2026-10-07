import 'dart:async';
import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

class FakeOcrEngine implements OcrEngine {
  FakeOcrEngine([this.result = const OcrResult(blocks: [])]);

  OcrResult result;
  final List<String> paths = [];

  @override
  Future<OcrResult> recognize(String absoluteImagePath) async {
    paths.add(absoluteImagePath);
    return result;
  }
}

OcrResult ocrOf(List<String> lines) => OcrResult(
  blocks: [
    OcrBlock(
      lines: [
        for (var i = 0; i < lines.length; i++)
          OcrLine(
            text: lines[i],
            left: 10,
            top: 40 * i,
            right: 600,
            bottom: 40 * i + 30,
          ),
      ],
    ),
  ],
);

class FakeEmbeddingRuntime implements EmbeddingRuntime {
  FakeEmbeddingRuntime({this.dimensions = 384});

  final int dimensions;
  final List<String> loads = [];
  final List<List<EncodedText>> batches = [];
  bool loaded = false;

  @override
  Future<bool> isLoaded() async => loaded;

  @override
  Future<void> load(String absoluteModelPath) async {
    loads.add(absoluteModelPath);
    loaded = true;
  }

  @override
  Future<List<Float32List>> run(List<EncodedText> batch) async {
    batches.add(batch);
    return [
      for (var i = 0; i < batch.length; i++) Float32List(dimensions)..[0] = 1,
    ];
  }
}

/// A generative runtime that replays scripted pieces of text.
///
/// Each entry in [script] is one reply, given as the pieces the runtime
/// would stream. It records what it was asked to load and generate, and
/// whether the consumer stopped reading part way through.
class ScriptedLlmRuntime implements LocalLlmRuntime {
  ScriptedLlmRuntime({
    List<List<String>>? script,
    this.memoryState = const DeviceMemory(
      totalBytes: 8 * 1024 * 1024 * 1024,
      availableBytes: 5 * 1024 * 1024 * 1024,
      lowRamDevice: false,
    ),
  }) : script = [...?script];

  /// Replies to hand out, each as a list of pieces.
  final List<List<String>> script;
  DeviceMemory memoryState;

  /// Thrown part way through the next reply when set.
  Object? failWith;

  final List<({String path, bool vision, int maxTokens})> loads = [];
  final List<({String prompt, List<Uint8List> images, int maxTokens})> prompts =
      [];

  /// Pieces the consumer actually read, per call.
  final List<List<String>> delivered = [];

  /// True when a consumer cancelled before the reply ran out.
  bool cancelled = false;
  int unloads = 0;
  String? _path;

  @override
  Future<void> load(
    String relativeModelPath, {
    required bool vision,
    int maxTokens = 1024,
  }) async {
    loads.add((path: relativeModelPath, vision: vision, maxTokens: maxTokens));
    _path = relativeModelPath;
  }

  @override
  Future<bool> isLoaded() async => _path != null;

  @override
  Future<String?> loadedModelPath() async => _path;

  @override
  Future<void> unload() async {
    unloads++;
    _path = null;
  }

  @override
  Stream<String> generate(
    String prompt, {
    List<Uint8List> images = const [],
    int maxTokens = 1024,
  }) {
    prompts.add((prompt: prompt, images: images, maxTokens: maxTokens));
    final pieces = script.isEmpty ? <String>[] : script.removeAt(0);
    final read = <String>[];
    delivered.add(read);
    var finished = false;
    late StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () async {
        for (final piece in pieces) {
          if (controller.isClosed) break;
          read.add(piece);
          controller.add(piece);
          // One event per microtask, so a consumer can stop in between.
          await Future<void>.delayed(Duration.zero);
          if (controller.isClosed) break;
        }
        if (failWith case final error?) {
          failWith = null;
          controller.addError(error);
        }
        finished = true;
        if (!controller.isClosed) await controller.close();
      },
      onCancel: () {
        if (!finished) cancelled = true;
      },
    );
    return controller.stream;
  }

  @override
  Future<DeviceMemory> memory() async => memoryState;
}

/// Imported model files, in memory.
class FakeLocalLlmFiles implements LocalLlmFiles {
  final List<InstalledLlmModel> models = [];

  /// Events the next [import] emits. The default accepts the file.
  List<ModelImportEvent>? importScript;
  final List<({String modelId, List<String> extensions})> imports = [];
  final List<String> removals = [];

  void install(
    String modelId, {
    String? path,
    int sizeBytes = 550 * 1024 * 1024,
  }) {
    models.add(
      InstalledLlmModel(
        modelId: modelId,
        relativePath: path ?? 'models/$modelId.task',
        sizeBytes: sizeBytes,
      ),
    );
  }

  @override
  Future<List<InstalledLlmModel>> installed() async => [...models];

  @override
  Stream<ModelImportEvent> import(
    String modelId, {
    required List<String> extensions,
  }) async* {
    imports.add((modelId: modelId, extensions: extensions));
    final script = importScript;
    if (script != null) {
      importScript = null;
      yield* Stream.fromIterable(script);
      return;
    }
    yield const ModelImportCopying(0.5);
    install(modelId);
    yield ModelImportDone(models.last);
  }

  /// Events the next [download] emits. The default accepts the file.
  List<ModelImportEvent>? downloadScript;
  final List<({String modelId, String token})> downloads = [];

  @override
  Stream<ModelImportEvent> download(
    String modelId, {
    required String token,
  }) async* {
    downloads.add((modelId: modelId, token: token));
    final script = downloadScript;
    if (script != null) {
      downloadScript = null;
      yield* Stream.fromIterable(script);
      return;
    }
    yield const ModelImportCopying(0.5);
    install(modelId);
    yield ModelImportDone(models.last);
  }

  @override
  Future<void> remove(String modelId) async {
    removals.add(modelId);
    models.removeWhere((model) => model.modelId == modelId);
  }
}

class FakeLocalModelFiles implements LocalModelFiles {
  final Map<String, LocalModelState> states = {};
  final Map<String, String> paths = {};

  @override
  Future<LocalModelState> state(String modelId) async =>
      states[modelId] ?? LocalModelState.notDownloaded;

  @override
  Future<String?> path(String modelId, String fileName) async =>
      paths['$modelId/$fileName'];

  @override
  Stream<double> download(String modelId) => const Stream.empty();

  @override
  Future<void> remove(String modelId) async {}
}

class InMemorySettingsStore implements SettingsStore {
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

class InMemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<List<String>> keys() async => values.keys.toList();

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
