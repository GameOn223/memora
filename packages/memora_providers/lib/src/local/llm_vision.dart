import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

import '../shared/json_extract.dart';
import '../shared/verification.dart';
import 'llm_prompt.dart';
import 'llm_session.dart';
import 'model_catalog.dart';

/// Vision with a Gemma model running on this phone.
///
/// It asks the same question every other vision adapter asks, with
/// [VisionPrompts] and the shared schema, and reads the reply with the same
/// lenient [extractJsonObject], so an understanding from here has the same
/// shape as one from Gemini.
///
/// A model loaded without vision gets nowhere near an image. The text-only
/// entries in the catalog keep [fallback], which is OCR plus rules, so
/// picking one of them for vision leaves that capability exactly as it was.
class LocalLlmVisionService implements VisionService {
  LocalLlmVisionService({
    required LocalLlmRuntime runtime,
    required LocalLlmFiles files,
    required this.spec,
    required this.fallback,
  }) : _session = LocalLlmSession(runtime: runtime, files: files, spec: spec);

  static const providerId = 'local';

  /// Room for a long `extracted_text` field.
  static const analyzeTokens = 1536;
  static const verifyTokens = 256;

  final LocalLlmSession _session;
  final LocalLlmSpec spec;

  /// OCR plus rules, used by a model that cannot read images.
  final VisionService fallback;

  @override
  Future<MemoryUnderstanding> analyze(VisionRequest request) async {
    if (!spec.vision) return fallback.analyze(request);
    final json = await _ask(
      instructions: VisionPrompts.analyzeInstructions(request),
      text: VisionPrompts.analyzeUserText,
      image: request.imageBytes,
      maxOutputTokens: analyzeTokens,
    );
    return MemoryUnderstanding.fromJson(json);
  }

  @override
  Future<VerificationResult> verify(VerificationRequest request) async {
    if (!spec.vision) return fallback.verify(request);
    final json = await _ask(
      instructions: VisionPrompts.verifyInstructions(request),
      text: verifyUserText,
      image: request.imageBytes,
      maxOutputTokens: verifyTokens,
    );
    return parseVerification(json);
  }

  Future<Map<String, Object?>> _ask({
    required String instructions,
    required String text,
    required int maxOutputTokens,
    required Uint8List image,
  }) async {
    if (image.isEmpty) {
      throw AiContentException(
        'On-device vision needs the image itself',
        providerId: providerId,
      );
    }
    final reply = await _session.run(
      LocalLlmPrompt.vision(instructions: instructions, text: text),
      capability: Capability.vision,
      images: [image],
      maxOutputTokens: maxOutputTokens,
    );
    final json = extractJsonObject(reply);
    if (json == null) {
      throw AiContentException(
        '${spec.displayName} did not return the expected JSON',
        providerId: providerId,
      );
    }
    return json;
  }
}
