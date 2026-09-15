import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

import '../http/errors.dart';
import '../shared/image_payload.dart';
import '../shared/json_extract.dart';
import '../shared/json_read.dart';
import '../shared/schema.dart';
import 'endpoint.dart';
import 'presets.dart';

final _formatRejected = RegExp(
  r'response_format|json_schema|json_object|structured output',
  caseSensitive: false,
);

const _verifyUserText = 'Check the field in this image.';

/// Vision over `POST /chat/completions` with an image data URI.
class OpenAiVisionService implements VisionService {
  OpenAiVisionService(this._endpoint, this._profile, this.modelId);

  final OpenAiEndpoint _endpoint;
  final OpenAiCompatibleProfile _profile;
  final String modelId;

  bool get _reasoning => isOpenAiReasoningModel(modelId);

  @override
  Future<MemoryUnderstanding> analyze(VisionRequest request) async {
    final json = await _requestJson(
      system: VisionPrompts.analyzeInstructions(request),
      userText: VisionPrompts.analyzeUserText,
      image: _image(request.imageBytes, request.mimeType),
      schemaName: 'memory_understanding',
      schema: VisionPrompts.understandingSchema,
      maxTokens: _reasoning && _profile.visionMaxTokens < 16000
          ? 16000
          : _profile.visionMaxTokens,
    );
    return MemoryUnderstanding.fromJson(json);
  }

  @override
  Future<VerificationResult> verify(VerificationRequest request) async {
    final json = await _requestJson(
      system: VisionPrompts.verifyInstructions(request),
      userText: _verifyUserText,
      image: _image(request.imageBytes, request.mimeType),
      schemaName: 'verification_result',
      schema: VisionPrompts.verificationSchema,
      maxTokens: _reasoning ? 4000 : 512,
    );
    return parseVerification(json);
  }

  ImagePayload _image(Uint8List bytes, String mimeType) =>
      ImagePayload.of(bytes, mimeType, providerId: _endpoint.providerId);

  /// Sends the request with the profile's JSON mode, and once more without
  /// it when the server rejects the option or the reply isn't JSON.
  Future<Map<String, Object?>> _requestJson({
    required String system,
    required String userText,
    required ImagePayload image,
    required String schemaName,
    required Map<String, Object?> schema,
    required int maxTokens,
  }) async {
    final messages = [
      {'role': 'system', 'content': system},
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': userText},
          {
            'type': 'image_url',
            'image_url': {'url': image.dataUri},
          },
        ],
      },
    ];

    Map<String, Object?> body({required bool withFormat}) => {
      'model': modelId,
      'messages': messages,
      if (!_reasoning) 'temperature': 0.1,
      if (withFormat) 'response_format': _responseFormat(schemaName, schema),
      _profile.maxTokensField: maxTokens,
    };

    Map<String, Object?>? first;
    try {
      first = await _endpoint.post('/chat/completions', body(withFormat: true));
    } on AiException catch (e) {
      if (e is AiTransientException || !_formatRejected.hasMatch(e.message)) {
        rethrow;
      }
    }
    if (first != null) {
      final parsed = _parseJsonReply(first);
      if (parsed != null) return parsed;
    }

    final second = await _endpoint.post(
      '/chat/completions',
      body(withFormat: false),
    );
    final parsed = _parseJsonReply(second);
    if (parsed != null) return parsed;
    throw AiContentException(
      'The model did not return the expected JSON',
      providerId: _endpoint.providerId,
    );
  }

  Map<String, Object?> _responseFormat(
    String name,
    Map<String, Object?> schema,
  ) {
    return switch (_profile.responseFormat) {
      JsonResponseFormat.jsonSchema => {
        'type': 'json_schema',
        'json_schema': {
          'name': name,
          'schema': closedSchema(schema),
          'strict': false,
        },
      },
      JsonResponseFormat.jsonObject => {'type': 'json_object'},
    };
  }

  Map<String, Object?>? _parseJsonReply(Map<String, Object?> json) {
    final choices = asList(json['choices']);
    final choice = choices.isEmpty ? null : asObject(choices.first);
    if (choice == null) {
      throw AiTransientException(
        'The provider returned no answer',
        providerId: _endpoint.providerId,
      );
    }
    final message = asObject(choice['message']) ?? const {};
    final refusal = asString(message['refusal']);
    if (refusal != null && refusal.trim().isNotEmpty) {
      throw AiContentException(
        'The model declined: ${shortenDetail(refusal)}',
        providerId: _endpoint.providerId,
      );
    }
    if (choice['finish_reason'] == 'content_filter') {
      throw AiContentException(
        'The provider filtered this image',
        providerId: _endpoint.providerId,
      );
    }
    return extractJsonObject(messageText(message['content']));
  }
}

/// Reads `{confirmed, observed_value}` leniently.
VerificationResult parseVerification(Map<String, Object?> json) {
  final confirmed = switch (json['confirmed']) {
    true || 'true' => true,
    _ => false,
  };
  final observed = switch (json['observed_value']) {
    final String s when s.trim().isNotEmpty => s.trim(),
    final num n => n.toString(),
    _ => null,
  };
  return VerificationResult(confirmed: confirmed, observedValue: observed);
}
