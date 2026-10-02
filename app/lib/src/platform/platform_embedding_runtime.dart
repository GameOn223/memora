import 'dart:math' as math;
import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

import 'messages.g.dart';

/// [EmbeddingRuntime] that runs an ONNX model through ONNX Runtime on the
/// Kotlin side.
class PlatformEmbeddingRuntime implements EmbeddingRuntime {
  PlatformEmbeddingRuntime({EmbeddingHostApi? host})
    : _host = host ?? EmbeddingHostApi();

  final EmbeddingHostApi _host;

  @override
  Future<void> load(String absoluteModelPath) => _host.load(absoluteModelPath);

  @override
  Future<bool> isLoaded() => _host.isLoaded();

  @override
  Future<List<Float32List>> run(List<EncodedText> batch) async {
    if (batch.isEmpty) return const [];
    final values = await _host.run(tokenBatchFrom(batch));
    return splitVectors(values, batch.length);
  }
}

/// Packs a batch row-major, padding shorter rows with zeros. Padding uses
/// token id 0 (`[PAD]`) with attention 0, so it doesn't change the result.
TokenBatch tokenBatchFrom(List<EncodedText> batch) {
  final length = batch.map((e) => e.inputIds.length).fold(0, math.max);
  final ids = Int64List(batch.length * length);
  final mask = Int64List(batch.length * length);
  final types = Int64List(batch.length * length);
  for (var row = 0; row < batch.length; row++) {
    final item = batch[row];
    final offset = row * length;
    ids.setRange(offset, offset + item.inputIds.length, item.inputIds);
    mask.setRange(
      offset,
      offset + item.attentionMask.length,
      item.attentionMask,
    );
    types.setRange(
      offset,
      offset + item.tokenTypeIds.length,
      item.tokenTypeIds,
    );
  }
  return TokenBatch(
    inputIds: ids,
    attentionMask: mask,
    tokenTypeIds: types,
    sequenceLength: length,
  );
}

/// Splits row-major doubles into one float vector per input.
List<Float32List> splitVectors(Float64List values, int rows) {
  if (rows <= 0 || values.length % rows != 0) {
    throw StateError(
      'Embedding output has ${values.length} values for $rows inputs',
    );
  }
  final dimensions = values.length ~/ rows;
  return [
    for (var row = 0; row < rows; row++)
      Float32List.fromList(
        values.sublist(row * dimensions, (row + 1) * dimensions),
      ),
  ];
}
