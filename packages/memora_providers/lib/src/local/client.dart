import 'package:memora_core/memora_core.dart';

import 'descriptor.dart';
import 'llm_chat.dart';
import 'llm_vision.dart';
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
  VisionService? vision(String modelId) {
    if (modelId == ocrRulesModelId) return _ocrVision;
    final spec = localLlmSpec(modelId);
    if (spec == null || !_runtime.hasLlm) return null;
    // A text-only model keeps the OCR path, so choosing one for vision
    // leaves that capability working exactly as it did.
    return LocalLlmVisionService(
      runtime: _runtime.llm!,
      files: _runtime.llmFiles!,
      spec: spec,
      fallback: _ocrVision,
    );
  }

  @override
  ChatService? chat(String modelId) {
    final spec = localLlmSpec(modelId);
    if (spec == null || !_runtime.hasLlm) return null;
    return LocalLlmChatService(
      runtime: _runtime.llm!,
      files: _runtime.llmFiles!,
      spec: spec,
    );
  }

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
  Future<List<String>> listModels(Capability capability) async {
    final suggested = descriptor.suggestedModels[capability] ?? const [];
    if (!_runtime.hasLlm) {
      return [
        for (final id in suggested)
          if (localLlmSpec(id) == null) id,
      ];
    }
    return suggested;
  }

  /// A generative model is a file the user imported, so it is only ready
  /// once that file is in app storage.
  ///
  /// The embedding model reports its own state when it runs, since a
  /// download it is in the middle of is worth showing as progress rather
  /// than as an unavailable capability.
  @override
  Future<bool> isModelReady(Capability capability, String modelId) async {
    if (localLlmSpec(modelId) == null) return true;
    final files = _runtime.llmFiles;
    if (files == null) return false;
    final installed = await files.installed();
    return installed.any((model) => model.modelId == modelId);
  }

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
      detail: 'Text recognition runs on this device. $embedding$_llmDetail',
    );
  }

  OcrVisionService get _ocrVision =>
      OcrVisionService(_runtime.ocr, _runtime.extractor);

  String get _llmDetail => _runtime.hasLlm
      ? ' A model you import can answer questions here too.'
      : '';
}
