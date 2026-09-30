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
