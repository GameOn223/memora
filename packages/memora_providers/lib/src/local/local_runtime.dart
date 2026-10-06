import 'package:memora_core/memora_core.dart';

/// The on-device ports the local provider runs on. The app builds this from
/// its platform adapters (ML Kit OCR, ONNX Runtime, model downloads).
class LocalRuntime {
  const LocalRuntime({
    required this.ocr,
    required this.embeddingRuntime,
    required this.modelFiles,
    this.extractor = const RuleBasedExtractor(),
    this.llm,
    this.llmFiles,
  });

  final OcrEngine ocr;

  /// Turns OCR output into a [MemoryUnderstanding].
  final OcrUnderstandingExtractor extractor;
  final EmbeddingRuntime embeddingRuntime;
  final LocalModelFiles modelFiles;

  /// Runs a generative model the user imported. Null on a build with no
  /// native runtime behind it, and then the provider offers no chat and
  /// vision stays on the OCR path.
  final LocalLlmRuntime? llm;

  /// The imported model files [llm] loads from.
  final LocalLlmFiles? llmFiles;

  /// Whether this build can run a generative model at all.
  bool get hasLlm => llm != null && llmFiles != null;
}
