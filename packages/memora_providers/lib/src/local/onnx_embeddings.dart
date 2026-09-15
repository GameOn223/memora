import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

import 'model_catalog.dart';

/// Embeddings from an ONNX sentence model running on the phone.
///
/// Tokenization happens here in Dart with [WordPieceTokenizer]. The token
/// ids go to the [EmbeddingRuntime], which runs the model natively and
/// returns pooled, normalized vectors.
class OnnxEmbeddingService implements EmbeddingService {
  OnnxEmbeddingService({
    required this._runtime,
    required this._modelFiles,
    this.spec = bgeSmallEnV15,
  });

  static const providerId = 'local';

  /// Prefix bge models expect on search queries, but not on documents.
  static const queryInstruction =
      'Represent this sentence for searching relevant passages: ';

  static const batchSize = 16;
  static const maxTokens = 512;

  /// Tokenizers by vocab path, shared so the vocab is read once per run.
  static final Map<String, Future<WordPieceTokenizer>> _tokenizers = {};

  final EmbeddingRuntime _runtime;
  final LocalModelFiles _modelFiles;
  final LocalModelSpec spec;
  String? _loadedPath;

  @override
  EmbeddingModelInfo get model => EmbeddingModelInfo(
    provider: providerId,
    modelId: spec.id,
    version: spec.revision.substring(0, 12),
    dimensions: spec.dimensions,
  );

  @override
  Future<List<Float32List>> embed(
    List<String> texts, {
    EmbeddingPurpose purpose = EmbeddingPurpose.document,
  }) async {
    if (texts.isEmpty) return const [];

    final notReady = CapabilityUnavailableException(
      Capability.embeddings,
      UnavailableReason.modelNotDownloaded,
      providerName: 'On this device',
    );
    if (await _modelFiles.state(spec.id) != LocalModelState.ready) {
      throw notReady;
    }
    final modelPath = await _modelFiles.path(spec.id, onnxModelFileName);
    final vocabPath = await _modelFiles.path(spec.id, vocabFileName);
    if (modelPath == null || vocabPath == null) throw notReady;

    final tokenizer = await _tokenizers.putIfAbsent(vocabPath, () async {
      final lines = await File(vocabPath).readAsLines();
      return WordPieceTokenizer.fromVocabLines(lines, maxLength: maxTokens);
    });
    if (_loadedPath != modelPath || !await _runtime.isLoaded()) {
      await _runtime.load(modelPath);
      _loadedPath = modelPath;
    }

    final inputs = purpose == EmbeddingPurpose.query
        ? [for (final text in texts) '$queryInstruction$text']
        : texts;
    final vectors = <Float32List>[];
    for (var start = 0; start < inputs.length; start += batchSize) {
      final batch = inputs.sublist(
        start,
        math.min(start + batchSize, inputs.length),
      );
      final output = await _runtime.run(tokenizer.encodeBatch(batch));
      if (output.length != batch.length) {
        throw AiTransientException(
          'The on-device model returned ${output.length} vectors for '
          '${batch.length} texts',
          providerId: providerId,
        );
      }
      for (final vector in output) {
        if (vector.length != spec.dimensions) {
          throw AiConfigurationException(
            'The on-device model returned ${vector.length} dimensions '
            'instead of ${spec.dimensions}. Download the model again.',
            providerId: providerId,
          );
        }
      }
      vectors.addAll(output);
    }
    return vectors;
  }
}
