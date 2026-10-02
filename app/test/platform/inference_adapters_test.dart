import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/platform/messages.g.dart';
import 'package:memora/src/platform/platform_embedding_runtime.dart';
import 'package:memora/src/platform/platform_ocr_engine.dart';
import 'package:memora_core/memora_core.dart';

void main() {
  test('packs a ragged batch row-major with zero padding', () {
    final batch = tokenBatchFrom([
      _encoded([101, 7, 102]),
      _encoded([101, 102]),
    ]);
    expect(batch.sequenceLength, 3);
    expect(batch.inputIds, [101, 7, 102, 101, 102, 0]);
    expect(batch.attentionMask, [1, 1, 1, 1, 1, 0]);
    expect(batch.tokenTypeIds, [0, 0, 0, 0, 0, 0]);
  });

  test('packs a single row without padding', () {
    final batch = tokenBatchFrom([
      _encoded([101, 7, 8, 102]),
    ]);

    expect(batch.sequenceLength, 4);
    expect(batch.inputIds, [101, 7, 8, 102]);
    expect(batch.attentionMask, [1, 1, 1, 1]);
  });

  test('pads every row to the longest one', () {
    final batch = tokenBatchFrom([
      _encoded([101, 102]),
      _encoded([101, 5, 6, 7, 102]),
      _encoded([101, 9, 102]),
    ]);

    expect(batch.sequenceLength, 5);
    expect(batch.inputIds.length, 15);
    expect(batch.inputIds.sublist(0, 5), [101, 102, 0, 0, 0]);
    expect(batch.attentionMask.sublist(0, 5), [1, 1, 0, 0, 0]);
    expect(batch.inputIds.sublist(10, 15), [101, 9, 102, 0, 0]);
    expect(batch.tokenTypeIds.every((value) => value == 0), isTrue);
  });

  test('splits doubles into float vectors', () {
    final vectors = splitVectors(Float64List.fromList([1, 0, 0, 0, 1, 0]), 2);
    expect(vectors, hasLength(2));
    expect(vectors[0], isA<Float32List>());
    expect(vectors[1], [0, 1, 0]);
    expect(() => splitVectors(Float64List(5), 2), throwsStateError);
  });

  test('runs a batch through the host', () async {
    final host = _FakeEmbeddingHost();
    final runtime = PlatformEmbeddingRuntime(host: host);

    final vectors = await runtime.run([
      _encoded([101, 102]),
      _encoded([101, 5, 102]),
    ]);

    expect(host.batches.single.sequenceLength, 3);
    expect(vectors.map((v) => v.length), [2, 2]);
    expect(vectors[1][0], closeTo(0.6, 1e-6));
  });

  test('an empty batch skips the bridge', () async {
    final runtime = PlatformEmbeddingRuntime(host: _FakeEmbeddingHost());
    expect(await runtime.run(const []), isEmpty);
  });

  test('maps OCR blocks and lines', () async {
    final engine = PlatformOcrEngine(host: _FakeOcrHost());

    final result = await engine.recognize('/data/files/originals/a.png');

    expect(result.text, 'Total\nRs 1,842\n\nDue 31 Aug');
    expect(result.blocks.first.lines.first.height, 10);
    expect(result.blocks.last.lines.single.left, 4);
  });
}

EncodedText _encoded(List<int> ids) => EncodedText(
  inputIds: Int64List.fromList(ids),
  attentionMask: Int64List.fromList(List.filled(ids.length, 1)),
  tokenTypeIds: Int64List(ids.length),
);

class _FakeEmbeddingHost extends EmbeddingHostApi {
  final batches = <TokenBatch>[];

  @override
  Future<Float64List> run(TokenBatch batch) async {
    batches.add(batch);
    return Float64List.fromList([1, 0, 0.6, 0.8]);
  }
}

class _FakeOcrHost extends OcrHostApi {
  @override
  Future<List<OcrBlockMessage>> recognize(String absolutePath) async => [
    OcrBlockMessage(
      lines: [
        OcrLineMessage(text: 'Total', left: 1, top: 2, right: 30, bottom: 12),
        OcrLineMessage(
          text: 'Rs 1,842',
          left: 1,
          top: 14,
          right: 40,
          bottom: 24,
        ),
      ],
    ),
    OcrBlockMessage(
      lines: [
        OcrLineMessage(
          text: 'Due 31 Aug',
          left: 4,
          top: 40,
          right: 50,
          bottom: 52,
        ),
      ],
    ),
  ];
}
