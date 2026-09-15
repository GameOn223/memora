import 'dart:math' as math;
import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

import '../shared/endpoint.dart';
import '../shared/json_read.dart';
import '../shared/vectors.dart';
import 'presets.dart';

/// Embeddings over `POST /embeddings`.
///
/// Stored vectors are tagged with [model], so its dimensions have to be
/// right. Common models are listed in [knownDimensions]. For anything else
/// the dimensions are learned from the first response and shared by every
/// later service for the same provider and model. Until that first call
/// returns, an unknown model reports 0 dimensions, so callers should read
/// [model] after [embed] when tagging vectors.
class OpenAiEmbeddingService implements EmbeddingService {
  OpenAiEmbeddingService(this._endpoint, this._profile, this.modelId);

  static const knownDimensions = {
    'text-embedding-3-small': 1536,
    'text-embedding-3-large': 3072,
    'text-embedding-ada-002': 1536,
    'nvidia/nv-embedqa-e5-v5': 1024,
    'nomic-embed-text': 768,
  };

  /// Largest number of texts sent in one request.
  static const batchSize = 64;

  static final Map<String, int> _learnedDimensions = {};

  final ProviderEndpoint _endpoint;
  final OpenAiCompatibleProfile _profile;
  final String modelId;

  String get _cacheKey => '${_endpoint.providerId}|$modelId';

  @override
  EmbeddingModelInfo get model => EmbeddingModelInfo(
    provider: _endpoint.providerId,
    modelId: modelId,
    version: '1',
    dimensions:
        _learnedDimensions[_cacheKey] ??
        knownDimensions[modelId] ??
        knownDimensions[modelId.split(':').first] ??
        0,
  );

  @override
  Future<List<Float32List>> embed(
    List<String> texts, {
    EmbeddingPurpose purpose = EmbeddingPurpose.document,
  }) async {
    if (texts.isEmpty) return const [];
    final vectors = <Float32List>[];
    for (var start = 0; start < texts.length; start += batchSize) {
      final batch = texts.sublist(
        start,
        math.min(start + batchSize, texts.length),
      );
      final json = await _endpoint.post('/embeddings', {
        'model': modelId,
        'input': batch,
        if (_profile.embeddingInputType) ...{
          'input_type': purpose == EmbeddingPurpose.query ? 'query' : 'passage',
          'encoding_format': 'float',
          'truncate': 'END',
        },
      });
      vectors.addAll(_parse(json, batch.length));
    }
    _learnedDimensions[_cacheKey] = vectors.first.length;
    return vectors;
  }

  List<Float32List> _parse(Map<String, Object?> json, int expected) {
    final items = <(int, List<Object?>)>[];
    final data = asList(json['data']);
    for (var i = 0; i < data.length; i++) {
      final item = asObject(data[i]);
      final embedding = item?['embedding'];
      if (item == null || embedding is! List) continue;
      final index = item['index'];
      items.add((index is int ? index : i, embedding.cast<Object?>()));
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));

    AiTransientException unexpected(String what) => AiTransientException(
      'The provider returned $what',
      providerId: _endpoint.providerId,
    );

    if (items.length != expected) {
      throw unexpected('${items.length} embeddings for $expected texts');
    }
    final List<Float32List> vectors;
    try {
      vectors = [for (final item in items) normalizedVector(item.$2)];
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
