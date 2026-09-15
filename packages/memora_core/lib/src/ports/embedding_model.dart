import 'package:meta/meta.dart';

/// Identifies an embedding space. Vectors from different models, versions or
/// dimensions are never compared.
@immutable
class EmbeddingModelInfo {
  const EmbeddingModelInfo({
    required this.provider,
    required this.modelId,
    required this.version,
    required this.dimensions,
  });

  /// Provider id, for example `local` or `openai`.
  final String provider;
  final String modelId;
  final String version;
  final int dimensions;

  /// The value stored in `embeddings.model_id`. Includes the provider so the
  /// same model name served by two providers stays separate.
  String get storageId => '$provider/$modelId';

  @override
  bool operator ==(Object other) =>
      other is EmbeddingModelInfo &&
      other.provider == provider &&
      other.modelId == modelId &&
      other.version == version &&
      other.dimensions == dimensions;

  @override
  int get hashCode => Object.hash(provider, modelId, version, dimensions);

  @override
  String toString() => '$storageId@$version (${dimensions}d)';
}
