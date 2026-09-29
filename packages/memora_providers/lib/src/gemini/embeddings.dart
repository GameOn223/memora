import 'dart:math' as math;
import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

import '../shared/endpoint.dart';
import '../shared/json_read.dart';
import '../shared/vectors.dart';
import 'response.dart';

/// Embeddings over `models/{model}:batchEmbedContents`.
///
/// `gemini-embedding-001` produces 3072 dimensions by default. Memora asks
/// for 768, which keeps vectors small, and normalizes them because Gemini
/// only normalizes the full-size output. Other models report the length of
/// the first response, the same way the OpenAI-compatible adapter does.
class GeminiEmbeddingService implements EmbeddingService {
  GeminiEmbeddingService(this._endpoint, String modelId)
    : modelId = bareModelId(modelId);

  /// Output size requested per model.
  static const requestedDimensions = {'gemini-embedding-001': 768};

  static const knownDimensions = {
    'gemini-embedding-001': 768,
    'text-embedding-004': 768,
  };

  /// Gemini accepts up to 100 requests in one batch.
  static const batchSize = 100;

  static final Map<String, int> _learnedDimensions = {};

  final ProviderEndpoint _endpoint;
  final String modelId;

  @override
  EmbeddingModelInfo get model => EmbeddingModelInfo(
    provider: _endpoint.providerId,
    modelId: modelId,
    version: '1',
    dimensions: _learnedDimensions[modelId] ?? knownDimensions[modelId] ?? 0,
  );

  @override
  Future<List<Float32List>> embed(
    List<String> texts, {
    EmbeddingPurpose purpose = EmbeddingPurpose.document,
  }) async {
    if (texts.isEmpty) return const [];
    final dimensions = requestedDimensions[modelId];
    final taskType = purpose == EmbeddingPurpose.query
        ? 'RETRIEVAL_QUERY'
        : 'RETRIEVAL_DOCUMENT';
    final vectors = <Float32List>[];
    for (var start = 0; start < texts.length; start += batchSize) {
      final batch = texts.sublist(
        start,
        math.min(start + batchSize, texts.length),
      );
      final json = await _endpoint.post('/models/$modelId:batchEmbedContents', {
        'requests': [
          for (final text in batch)
            {
              'model': 'models/$modelId',
              'content': {
                'parts': [
                  {'text': text},
                ],
              },
              'taskType': taskType,
              'outputDimensionality': ?dimensions,
            },
        ],
      });
      vectors.addAll(_parse(json, batch.length));
    }
    _learnedDimensions[modelId] = vectors.first.length;
    return vectors;
  }

  List<Float32List> _parse(Map<String, Object?> json, int expected) {
    AiTransientException unexpected(String what) => AiTransientException(
      'Gemini returned $what',
      providerId: _endpoint.providerId,
    );

    final embeddings = asList(json['embeddings']);
    if (embeddings.length != expected) {
      throw unexpected('${embeddings.length} embeddings for $expected texts');
    }
    final List<Float32List> vectors;
    try {
      vectors = [
        for (final item in embeddings)
          normalizedVector(asList(asObject(item)?['values'])),
      ];
    } on FormatException {
      throw unexpected('embeddings in an unexpected format');
    }
    final length = vectors.first.length;
    if (length == 0 || vectors.any((v) => v.length != length)) {
      throw unexpected('embeddings of different lengths');
    }
    return vectors;
  }
}
