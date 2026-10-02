import 'dart:math' as math;
import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

import '../shared/endpoint.dart';
import '../shared/json_read.dart';
import '../shared/model_facts.dart';
import '../shared/vectors.dart';
import 'presets.dart';

/// Embeddings over `POST /embeddings`.
///
/// Stored vectors are tagged with [model], so its dimensions have to be
/// right. Well known models are in `openAiCompatibleEmbeddingDimensions`.
/// For anything else the length comes from the provider, learned on the
/// first response and shared by every later service for the same provider
/// and model. Call [resolveModel] before tagging vectors and the answer is
/// never a guess.
class OpenAiEmbeddingService implements EmbeddingService {
  OpenAiEmbeddingService(this._endpoint, this._profile, this.modelId);

  /// Largest number of texts sent in one request.
  static const batchSize = 64;

  static final Map<String, int> _learnedDimensions = {};

  final ProviderEndpoint _endpoint;
  final OpenAiCompatibleProfile _profile;
  final String modelId;

  /// `nomic-embed-text` and `nomic-embed-text:latest` are the same model, so
  /// they have to share one storage id or their vectors never compare.
  String get _storageModelId => modelId.endsWith(':latest')
      ? modelId.substring(0, modelId.length - ':latest'.length)
      : modelId;

  String get _cacheKey => '${_endpoint.providerId}|$_storageModelId';

  @override
  EmbeddingModelInfo get model => EmbeddingModelInfo(
    provider: _endpoint.providerId,
    modelId: _storageModelId,
    version: '1',
    dimensions:
        _learnedDimensions[_cacheKey] ??
        openAiCompatibleEmbeddingDimensions[_storageModelId] ??
        0,
  );

  /// [model] with its real dimensions, asking the provider once when they
  /// aren't known yet. Costs one embedding of a single token.
  Future<EmbeddingModelInfo> resolveModel() async {
    if (model.dimensions > 0) return model;
    await embed(const ['a']);
    return model;
  }

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
