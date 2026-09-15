import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

import '../shared/endpoint.dart';
import '../shared/image_payload.dart';
import '../shared/json_extract.dart';
import '../shared/verification.dart';
import 'response.dart';
import 'schema.dart';

/// Image types Gemini accepts inline.
const geminiImageMimeTypes = {
  'image/png',
  'image/jpeg',
  'image/webp',
  'image/heic',
  'image/heif',
};

/// Vision over `models/{model}:generateContent` with a response schema.
class GeminiVisionService implements VisionService {
  GeminiVisionService(this._endpoint, String modelId)
    : modelId = bareModelId(modelId);

  final ProviderEndpoint _endpoint;
  final String modelId;

  @override
  Future<MemoryUnderstanding> analyze(VisionRequest request) async {
    final json = await _generateJson(
      system: VisionPrompts.analyzeInstructions(request),
      userText: VisionPrompts.analyzeUserText,
      image: _image(request.imageBytes, request.mimeType),
      schema: VisionPrompts.understandingSchema,
    );
    return MemoryUnderstanding.fromJson(json);
  }

  @override
  Future<VerificationResult> verify(VerificationRequest request) async {
    final json = await _generateJson(
      system: VisionPrompts.verifyInstructions(request),
      userText: verifyUserText,
      image: _image(request.imageBytes, request.mimeType),
      schema: VisionPrompts.verificationSchema,
    );
    return parseVerification(json);
  }

  ImagePayload _image(Uint8List bytes, String mimeType) => ImagePayload.of(
    bytes,
    mimeType,
    providerId: _endpoint.providerId,
    supportedMimeTypes: geminiImageMimeTypes,
  );

  Future<Map<String, Object?>> _generateJson({
    required String system,
    required String userText,
    required ImagePayload image,
    required Map<String, Object?> schema,
  }) async {
    final json = await _endpoint.post('/models/$modelId:generateContent', {
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': userText},
            {
              'inline_data': {
                'mime_type': image.mimeType,
                'data': image.base64Data,
              },
            },
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.1,
        'responseMimeType': 'application/json',
        'responseSchema': geminiSchema(schema),
      },
    });

    final candidate = firstCandidate(json);
    final finishReason = candidate?['finishReason'];
    if (candidate == null || blockedFinishReasons.contains(finishReason)) {
      throw AiContentException(
        finishReason == null
            ? 'Gemini returned no answer for this image'
            : 'Gemini withheld the answer ($finishReason)',
        providerId: _endpoint.providerId,
      );
    }
    final parsed = extractJsonObject(partsText(candidateParts(candidate)));
    if (parsed == null) {
      throw AiContentException(
        finishReason == 'MAX_TOKENS'
            ? 'The answer was cut off before the JSON was complete'
            : 'The model did not return the expected JSON',
        providerId: _endpoint.providerId,
      );
    }
    return parsed;
  }
}
