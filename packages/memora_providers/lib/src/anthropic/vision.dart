import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

import '../shared/endpoint.dart';
import '../shared/image_payload.dart';
import '../shared/json_extract.dart';
import '../shared/json_read.dart';
import '../shared/model_facts.dart';
import '../shared/schema.dart';
import '../shared/verification.dart';
import 'messages.dart';

/// Image types the Messages API accepts.
const anthropicImageMimeTypes = {
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
};

/// Largest image the Messages API accepts.
const anthropicMaxImageBytes = 5 * 1024 * 1024;

/// Vision over `POST /messages`, getting structured output by asking the
/// model to call a tool whose input schema is the shape Memora wants.
class AnthropicVisionService implements VisionService {
  AnthropicVisionService(this._endpoint, this.modelId);

  final ProviderEndpoint _endpoint;
  final String modelId;

  @override
  Future<MemoryUnderstanding> analyze(VisionRequest request) async {
    final input = await _requestJson(
      system: VisionPrompts.analyzeInstructions(request),
      userText: VisionPrompts.analyzeUserText,
      image: _image(request.imageBytes, request.mimeType),
      toolName: 'record_memory',
      toolDescription: 'Record the data extracted from the image.',
      schema: VisionPrompts.understandingSchema,
      maxTokens: 16000,
    );
    return MemoryUnderstanding.fromJson(input);
  }

  @override
  Future<VerificationResult> verify(VerificationRequest request) async {
    final input = await _requestJson(
      system: VisionPrompts.verifyInstructions(request),
      userText: verifyUserText,
      image: _image(request.imageBytes, request.mimeType),
      toolName: 'record_verification',
      toolDescription: 'Record whether the image shows the expected value.',
      schema: VisionPrompts.verificationSchema,
      maxTokens: 4096,
    );
    return parseVerification(input);
  }

  ImagePayload _image(Uint8List bytes, String mimeType) => ImagePayload.of(
    bytes,
    mimeType,
    providerId: _endpoint.providerId,
    maxBytes: anthropicMaxImageBytes,
    supportedMimeTypes: anthropicImageMimeTypes,
  );

  /// Asks for JSON the way [modelId] supports.
  ///
  /// Current models take `output_config.format` and answer with the JSON as
  /// text. Anything else, including a model released after this was written,
  /// gets a tool it may call plus an instruction to use it. Forced
  /// `tool_choice` is never sent: the current lineup rejects it with a 400,
  /// which would fail every image and pause the queue.
  Future<Map<String, Object?>> _requestJson({
    required String system,
    required String userText,
    required ImagePayload image,
    required String toolName,
    required String toolDescription,
    required Map<String, Object?> schema,
    required int maxTokens,
  }) async {
    final structured = anthropicSupportsStructuredOutput(modelId);
    final json = await _endpoint.post('/messages', {
      'model': modelId,
      'max_tokens': maxTokens,
      'system': system,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': image.mimeType,
                'data': image.base64Data,
              },
            },
            {
              'type': 'text',
              'text': structured
                  ? userText
                  : '$userText Record the result with the $toolName tool.',
            },
          ],
        },
      ],
      if (structured)
        'output_config': {
          'format': {'type': 'json_schema', 'schema': closedSchema(schema)},
        }
      else ...{
        'tools': [
          {
            'name': toolName,
            'description': toolDescription,
            'input_schema': schema,
          },
        ],
        'tool_choice': {'type': 'auto'},
      },
    });

    final stopReason = json['stop_reason'];
    if (stopReason == 'refusal') {
      throw AiContentException(
        'The model declined to process this image',
        providerId: _endpoint.providerId,
      );
    }
    final content = asList(json['content']);
    for (final raw in content) {
      final block = asObject(raw);
      if (block?['type'] == 'tool_use' && block?['name'] == toolName) {
        final input = asObject(block?['input']);
        if (input != null) return input;
      }
    }
    final fromText = extractJsonObject(responseText(content));
    if (fromText != null) return fromText;
    throw AiContentException(
      stopReason == 'max_tokens'
          ? 'The answer was cut off before it was complete'
          : 'The model did not return the expected data',
      providerId: _endpoint.providerId,
    );
  }
}
