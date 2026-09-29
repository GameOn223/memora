import 'dart:io';
import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';
import 'package:memora_providers/memora_providers.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';

const _vocab = [
  '[PAD]',
  '[unused0]',
  '[UNK]',
  '[CLS]',
  '[SEP]',
  'represent',
  'this',
  'sentence',
  'for',
  'searching',
  'relevant',
  'passages',
  ':',
  'airtel',
  'bill',
  'receipt',
];

VisionRequest _vision({String? path = '/data/files/originals/a.png'}) =>
    VisionRequest(
      imageBytes: Uint8List(0),
      mimeType: 'image/png',
      takenAt: DateTime(2026, 9, 1),
      absoluteImagePath: path,
    );

VerificationRequest _verify(
  String expected, {
  String? path = '/data/a.png',
  String type = 'amount',
}) => VerificationRequest(
  imageBytes: Uint8List(0),
  mimeType: 'image/png',
  attributeType: type,
  expectedValue: expected,
  absoluteImagePath: path,
);

class _RecordingExtractor implements OcrUnderstandingExtractor {
  final calls = <(OcrResult, DateTime)>[];

  @override
  MemoryUnderstanding extract(OcrResult ocr, {required DateTime takenAt}) {
    calls.add((ocr, takenAt));
    return const MemoryUnderstanding(summary: 'from rules', category: 'other');
  }
}

void main() {
  late FakeOcrEngine ocr;
  late FakeEmbeddingRuntime runtime;
  late FakeLocalModelFiles files;
  late Directory temp;

  setUp(() {
    ocr = FakeOcrEngine();
    runtime = FakeEmbeddingRuntime();
    files = FakeLocalModelFiles();
    temp = Directory.systemTemp.createTempSync('memora_local_test');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  void markDownloaded() {
    final vocab = File('${temp.path}/vocab.txt')
      ..writeAsStringSync('${_vocab.join('\n')}\n');
    files.states[bgeSmallEnV15.id] = LocalModelState.ready;
    files.paths['${bgeSmallEnV15.id}/vocab.txt'] = vocab.path;
    files.paths['${bgeSmallEnV15.id}/model_quantized.onnx'] =
        '${temp.path}/model_quantized.onnx';
  }

  LocalRuntime local({OcrUnderstandingExtractor? extractor}) => LocalRuntime(
    ocr: ocr,
    extractor: extractor ?? const RuleBasedExtractor(),
    embeddingRuntime: runtime,
    modelFiles: files,
  );

  group('descriptor and catalog', () {
    test('describes the on-device provider', () {
      expect(localDescriptor.id, 'local');
      expect(localDescriptor.displayName, 'On this device');
      expect(localDescriptor.location, ProviderLocation.onDevice);
      expect(localDescriptor.requiresApiKey, isFalse);
      expect(localDescriptor.capabilities, {
        Capability.vision,
        Capability.embeddings,
        Capability.reranking,
      });
      expect(localDescriptor.defaultModel(Capability.vision), 'ocr-rules');
      expect(
        localDescriptor.defaultModel(Capability.embeddings),
        'bge-small-en-v1.5',
      );
      expect(
        localDescriptor.defaultModel(Capability.reranking),
        'score-fusion',
      );
    });

    test('pins bge-small-en-v1.5 to a revision with checksums', () {
      expect(bgeSmallEnV15.id, 'bge-small-en-v1.5');
      expect(bgeSmallEnV15.displayName, 'bge-small-en v1.5');
      expect(
        bgeSmallEnV15.revision,
        'ea104dacec62c0de699686887e3f920caeb4f3e3',
      );
      expect(bgeSmallEnV15.dimensions, 384);

      final model = bgeSmallEnV15.file('model_quantized.onnx')!;
      expect(
        model.uri,
        Uri.parse(
          'https://huggingface.co/Xenova/bge-small-en-v1.5/resolve/'
          'ea104dacec62c0de699686887e3f920caeb4f3e3/onnx/model_quantized.onnx',
        ),
      );
      expect(model.size, 34014426);
      expect(
        model.sha256,
        '6c9c6101a956d62dfb5e7190c538226c0c5bb9cb27b651234b6df063ee7dbfe4',
      );

      final vocab = bgeSmallEnV15.file('vocab.txt')!;
      expect(
        vocab.url,
        'https://huggingface.co/Xenova/bge-small-en-v1.5/resolve/'
        'ea104dacec62c0de699686887e3f920caeb4f3e3/vocab.txt',
      );
      expect(vocab.size, 231508);
      expect(vocab.gitBlobSha1, 'fb140275c155a9c7c5a3b3e0e77a9e839594a938');
      expect(vocab.sha256, isNull);

      expect(bgeSmallEnV15.totalBytes, 34014426 + 231508);
      expect(bgeSmallEnV15.file('missing.bin'), isNull);
      expect(localModelCatalog, [bgeSmallEnV15]);
      expect(localModelSpec('bge-small-en-v1.5'), same(bgeSmallEnV15));
      expect(localModelSpec('nope'), isNull);
    });
  });

  group('OCR vision', () {
    test(
      'runs OCR on the file and hands the result to the extractor',
      () async {
        final extractor = _RecordingExtractor();
        ocr.result = ocrOf(['Airtel', 'Total due ₹799']);
        final vision = LocalProviderClient(local(extractor: extractor))
            .vision('ocr-rules')!;

        final u = await vision.analyze(_vision());

        expect(ocr.paths, ['/data/files/originals/a.png']);
        expect(u.summary, 'from rules');
        expect(extractor.calls.single.$1, same(ocr.result));
        expect(extractor.calls.single.$2, DateTime(2026, 9, 1));
      },
    );

    test('works with the rule-based extractor from core', () async {
      ocr.result = ocrOf([
        'Reliance Energy',
        'Electricity bill',
        'Amount due ₹1,842',
      ]);
      final u = await LocalProviderClient(local())
          .vision('ocr-rules')!
          .analyze(_vision());
      expect(u.extractedText, contains('Amount due'));
    });

    test('needs the image path', () async {
      final vision = LocalProviderClient(local()).vision('ocr-rules')!;
      await expectLater(
        vision.analyze(_vision(path: null)),
        throwsA(
          isA<AiContentException>().having(
            (e) => e.providerId,
            'providerId',
            'local',
          ),
        ),
      );
      await expectLater(
        vision.verify(_verify('₹1', path: null)),
        throwsA(isA<AiContentException>()),
      );
      expect(ocr.paths, isEmpty);
    });

    test('verify confirms when the digits appear in the text', () async {
      ocr.result = ocrOf([
        'Invoice 88',
        'Total ₹2,103.00',
        'Paid on 05/09/2026',
      ]);
      final vision = LocalProviderClient(local()).vision('ocr-rules')!;

      final confirmed = await vision.verify(_verify('₹2,103'));
      expect(confirmed.confirmed, isTrue);
      expect(confirmed.observedValue, isNull);

      expect((await vision.verify(_verify('2103.00'))).confirmed, isTrue);
      expect((await vision.verify(_verify('₹2,130'))).confirmed, isFalse);
      expect((await vision.verify(_verify('₹21'))).confirmed, isFalse);
      expect((await vision.verify(_verify('no digits'))).confirmed, isFalse);
    });

    test('an amount needs a line that looks like money', () async {
      // 702 here is an order number, not the total.
      ocr.result = ocrOf(['Order 702', 'Items 3', 'Delivered']);
      final vision = LocalProviderClient(local()).vision('ocr-rules')!;

      expect((await vision.verify(_verify('₹702'))).confirmed, isFalse);
      expect(
        (await vision.verify(_verify('702', type: 'order_number'))).confirmed,
        isTrue,
        reason: 'the same digits confirm for a field that is not money',
      );
    });

    test('a value with several numbers is never confirmed', () async {
      ocr.result = ocrOf(['Due 31/08/2026', 'Total ₹500']);
      final vision = LocalProviderClient(local()).vision('ocr-rules')!;
      final result = await vision.verify(
        _verify('2026-08-31', type: 'due_date'),
      );
      expect(result.confirmed, isFalse);
      expect(result.observedValue, isNull);
    });

    test('verify reads Indian digit grouping', () async {
      ocr.result = ocrOf(['MacBook Air', 'Price ₹1,24,900']);
      final vision = LocalProviderClient(local()).vision('ocr-rules')!;
      expect((await vision.verify(_verify('124900'))).confirmed, isTrue);
    });
  });

  group('ONNX embeddings', () {
    test('reports the pinned model', () {
      final service = LocalProviderClient(local())
          .embeddings('bge-small-en-v1.5')!;
      expect(
        service.model,
        const EmbeddingModelInfo(
          provider: 'local',
          modelId: 'bge-small-en-v1.5',
          version: 'ea104dacec62',
          dimensions: 384,
        ),
      );
    });

    test('refuses to run before the model is downloaded', () async {
      final service = LocalProviderClient(local())
          .embeddings('bge-small-en-v1.5')!;
      await expectLater(
        service.embed(['bill']),
        throwsA(
          isA<CapabilityUnavailableException>()
              .having((e) => e.capability, 'capability', Capability.embeddings)
              .having(
                (e) => e.reason,
                'reason',
                UnavailableReason.modelNotDownloaded,
              ),
        ),
      );
      expect(runtime.loads, isEmpty);
    });

    test('loads the model once and embeds in batches of 16', () async {
      markDownloaded();
      final service = LocalProviderClient(local())
          .embeddings('bge-small-en-v1.5')!;

      final vectors = await service.embed([
        for (var i = 0; i < 20; i++) 'airtel bill',
      ]);
      await service.embed(['receipt']);

      expect(vectors, hasLength(20));
      expect(vectors.first, hasLength(384));
      expect(runtime.loads, ['${temp.path}/model_quantized.onnx']);
      expect(runtime.batches.map((b) => b.length), [16, 4, 1]);
      final first = runtime.batches.first.first;
      expect(first.inputIds, [3, 13, 14, 4]);
      expect(first.attentionMask, [1, 1, 1, 1]);
    });

    test('queries get the retrieval instruction', () async {
      markDownloaded();
      final service = LocalProviderClient(local())
          .embeddings('bge-small-en-v1.5')!;

      await service.embed(['airtel bill'], purpose: EmbeddingPurpose.query);

      expect(
        OnnxEmbeddingService.queryInstruction,
        'Represent this sentence for searching relevant passages: ',
      );
      expect(runtime.batches.single.single.inputIds, [
        3,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        4,
      ]);
    });

    test('a second service does not reload the model', () async {
      markDownloaded();
      final client = LocalProviderClient(local());

      // The router builds a new service for every call.
      await client.embeddings('bge-small-en-v1.5')!.embed(['bill']);
      await client.embeddings('bge-small-en-v1.5')!.embed(['receipt']);

      expect(runtime.loads, hasLength(1));
      expect(runtime.batches, hasLength(2));
    });

    test('reloads when the runtime lost the model', () async {
      markDownloaded();
      final service = LocalProviderClient(local())
          .embeddings('bge-small-en-v1.5')!;
      await service.embed(['bill']);
      runtime.loaded = false;
      await service.embed(['bill']);
      expect(runtime.loads, hasLength(2));
    });

    test('a vector of the wrong size is a configuration problem', () async {
      markDownloaded();
      runtime = FakeEmbeddingRuntime(dimensions: 768);
      final service = LocalProviderClient(local())
          .embeddings('bge-small-en-v1.5')!;
      await expectLater(
        service.embed(['bill']),
        throwsA(isA<AiConfigurationException>()),
      );
    });

    test('empty input does nothing', () async {
      final service = LocalProviderClient(local())
          .embeddings('bge-small-en-v1.5')!;
      expect(await service.embed([]), isEmpty);
    });
  });

  group('client', () {
    test('only knows its own model ids', () {
      final client = LocalProviderClient(local());
      expect(client.descriptor, same(localDescriptor));
      expect(client.vision('ocr-rules'), isA<OcrVisionService>());
      expect(client.vision('gpt-5-mini'), isNull);
      expect(
        client.embeddings('bge-small-en-v1.5'),
        isA<OnnxEmbeddingService>(),
      );
      expect(client.embeddings('nomic-embed-text'), isNull);
      expect(client.reranker('score-fusion'), isA<FusionReranker>());
      expect(client.reranker('other'), isNull);
      expect(client.chat('anything'), isNull);
    });

    test('reranks with score fusion', () async {
      final scores = await LocalProviderClient(local())
          .reranker('score-fusion')!
          .rerank('airtel', const [
            RerankCandidate(id: 'a', text: 'Swiggy receipt', priorScore: 0.5),
            RerankCandidate(id: 'b', text: 'Airtel bill', priorScore: 0.4),
          ]);
      expect(scores.first.id, 'b');
    });

    test('lists suggested models', () async {
      final client = LocalProviderClient(local());
      expect(await client.listModels(Capability.embeddings), [
        'bge-small-en-v1.5',
      ]);
      expect(await client.listModels(Capability.chat), isEmpty);
    });

    test('testConnection reports the embedding model state', () async {
      final client = LocalProviderClient(local());
      final missing = await client.testConnection();
      expect(missing.ok, isTrue);
      expect(missing.detail, contains('not downloaded'));

      markDownloaded();
      final ready = await client.testConnection();
      expect(ready.ok, isTrue);
      expect(ready.detail, contains('ready'));
    });
  });
}
