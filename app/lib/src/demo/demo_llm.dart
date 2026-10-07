import 'dart:async';
import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

/// A generative runtime for demo builds and widget tests.
///
/// It streams a canned reply a few characters at a time, so the settings
/// rows, the chat header and the import flow behave as they would with a
/// model loaded, without a model on disk.
class DemoLlmRuntime implements LocalLlmRuntime {
  DemoLlmRuntime({
    this.memoryState = const DeviceMemory(
      // A mid-range phone: room for the small model, not the large one.
      totalBytes: 3 * 1024 * 1024 * 1024,
      availableBytes: 2 * 1024 * 1024 * 1024 + 512 * 1024 * 1024,
      lowRamDevice: false,
    ),
    this.step = const Duration(milliseconds: 40),
  });

  /// What the phone reports, which decides what settings says about each
  /// catalog entry.
  DeviceMemory memoryState;

  /// Delay between generated pieces. Tests set it to zero.
  Duration step;

  /// Pieces of the next reply. The default is a tool call, since the chat
  /// engine asks for one first.
  List<String> reply = const [
    '{"tool": "search_memories", ',
    '"arguments": {"text": "bills"}}',
    '<end_of_turn>',
  ];

  String? _path;

  @override
  Future<void> load(
    String relativeModelPath, {
    required bool vision,
    int maxTokens = 1024,
  }) async {
    _path = relativeModelPath;
  }

  @override
  Future<bool> isLoaded() async => _path != null;

  @override
  Future<String?> loadedModelPath() async => _path;

  @override
  Future<void> unload() async => _path = null;

  @override
  Stream<String> generate(
    String prompt, {
    List<Uint8List> images = const [],
    int maxTokens = 1024,
  }) async* {
    for (final piece in reply) {
      await Future<void>.delayed(step);
      yield piece;
    }
  }

  final _loading = StreamController<LlmLoading?>.broadcast();

  @override
  Stream<LlmLoading?> get loading => _loading.stream;

  /// Pretends a load is under way, so the indicator can be seen.
  void showLoading({
    String path = 'models/imported/demo.task',
    int tokens = 4096,
  }) => _loading.add(LlmLoading(relativePath: path, maxTokens: tokens));

  void finishLoading() => _loading.add(null);

  @override
  Future<DeviceMemory> memory() async => memoryState;
}

/// Imported model files for demo builds, held in memory.
class DemoLlmFiles implements LocalLlmFiles {
  DemoLlmFiles({this.step = const Duration(milliseconds: 80)});

  /// Delay between copy updates. Tests set it to zero.
  Duration step;
  final List<InstalledLlmModel> models = [];

  /// What the picker returns next. `null` accepts the file.
  ModelImportRefusal? refuseNext;

  /// When set, the picker closes without a file.
  bool cancelNext = false;

  @override
  Future<List<InstalledLlmModel>> installed() async => [...models];

  @override
  Stream<ModelImportEvent> import(
    String modelId, {
    required List<String> extensions,
  }) async* {
    if (cancelNext) {
      cancelNext = false;
      yield const ModelImportCancelled();
      return;
    }
    if (refuseNext case final reason?) {
      refuseNext = null;
      yield ModelImportRefused(reason, fileName: 'gemma-3-1b-it.gguf');
      return;
    }
    for (var done = 1; done <= 4; done++) {
      await Future<void>.delayed(step);
      yield ModelImportCopying(done / 4);
    }
    final model = InstalledLlmModel(
      modelId: modelId,
      relativePath: 'models/$modelId${extensions.first}',
      sizeBytes: 550 * 1024 * 1024,
    );
    models.add(model);
    yield ModelImportDone(model);
  }

  /// Tokens the downloads were handed, so a test can check one came out of
  /// the secret store rather than being invented here.
  final List<String> tokensSeen = [];

  @override
  Stream<ModelImportEvent> download(
    String modelId, {
    required String token,
  }) async* {
    tokensSeen.add(token);
    if (refuseNext case final reason?) {
      refuseNext = null;
      yield ModelImportRefused(reason);
      return;
    }
    for (var done = 1; done <= 4; done++) {
      await Future<void>.delayed(step);
      yield ModelImportCopying(done / 4);
    }
    final model = InstalledLlmModel(
      modelId: modelId,
      relativePath: 'models/imported/$modelId.task',
      sizeBytes: 550 * 1024 * 1024,
    );
    models.add(model);
    yield ModelImportDone(model);
  }

  /// The download a demo build pretends is already running.
  String? running;

  @override
  Stream<ModelImportEvent> watchDownload(String modelId) =>
      download(modelId, token: 'demo');

  @override
  Future<String?> activeDownload() async => running;

  @override
  Future<void> cancelDownload() async => running = null;

  @override
  Future<void> remove(String modelId) async =>
      models.removeWhere((model) => model.modelId == modelId);
}
