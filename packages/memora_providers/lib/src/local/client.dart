import 'package:memora_core/memora_core.dart';

import 'descriptor.dart';
import 'local_runtime.dart';
import 'model_catalog.dart';
import 'ocr_vision.dart';
import 'onnx_embeddings.dart';

/// [ProviderClient] for capabilities that run on the phone. Nothing here
/// touches the network.
class LocalProviderClient implements ProviderClient {
  LocalProviderClient(this._runtime);

  final LocalRuntime _runtime;

  @override
  ProviderDescriptor get descriptor => localDescriptor;

  @override
  VisionService? vision(String modelId) => modelId == ocrRulesModelId
      ? OcrVisionService(_runtime.ocr, _runtime.extractor)
      : null;

  @override
  ChatService? chat(String modelId) => null;

  @override
  EmbeddingService? embeddings(String modelId) {
    final spec = localModelSpec(modelId);
    return spec == null
        ? null
        : OnnxEmbeddingService(
            runtime: _runtime.embeddingRuntime,
            modelFiles: _runtime.modelFiles,
            spec: spec,
          );
  }

  @override
  RerankService? reranker(String modelId) =>
      modelId == scoreFusionModelId ? const FusionReranker() : null;

  @override
  Future<List<String>> listModels(Capability capability) async =>
      descriptor.suggestedModels[capability] ?? const [];

  @override
  Future<ConnectionCheck> testConnection() async {
    final state = await _runtime.modelFiles.state(bgeSmallEnV15.id);
    final embedding = switch (state) {
      LocalModelState.ready => 'The embedding model is ready.',
      LocalModelState.downloading => 'The embedding model is downloading.',
      LocalModelState.failed => 'The embedding model download failed.',
      LocalModelState.notDownloaded =>
        'The embedding model is not downloaded yet.',
    };
    return ConnectionCheck.ok(
      detail: 'Text recognition runs on this device. $embedding',
    );
  }
}
