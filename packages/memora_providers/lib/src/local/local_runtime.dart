import 'package:memora_core/memora_core.dart';

/// The on-device ports the local provider runs on. The app builds this from
/// its platform adapters (ML Kit OCR, ONNX Runtime, model downloads).
class LocalRuntime {
  const LocalRuntime({
    required this.ocr,
    required this.embeddingRuntime,
    required this.modelFiles,
    this.extractor = const RuleBasedExtractor(),
  });

  final OcrEngine ocr;

  /// Turns OCR output into a [MemoryUnderstanding].
  final OcrUnderstandingExtractor extractor;
  final EmbeddingRuntime embeddingRuntime;
  final LocalModelFiles modelFiles;
}
