import 'package:memora_core/memora_core.dart';
import 'package:memora_providers/memora_providers.dart';
import 'package:test/test.dart';

import '../support/scripted_http.dart';

void main() {
  late ScriptedHttp http;

  setUp(() => http = ScriptedHttp());

  NvidiaRerankService service(String model) => NvidiaRerankService(
    httpClient: http.client,
    apiKey: 'nvapi-test-000000',
    modelId: model,
  );

  const candidates = [
    RerankCandidate(id: 'm1', text: 'Reliance electricity bill ₹1,842'),
    RerankCandidate(id: 'm2', text: 'Swiggy order receipt'),
    RerankCandidate(id: 'm3', text: 'Reliance electricity bill ₹2,103'),
  ];

  test('sends passages and maps rankings back to ids by logit', () async {
    http.replyFixture('nvidia/rerank_response.json');

    final scores = await service('nvidia/nv-rerankqa-mistral-4b-v3')
        .rerank('highest electricity bill', candidates);

    final request = http.requests.single;
    expect(
      request.url.toString(),
      'https://ai.api.nvidia.com/v1/retrieval/nvidia/nv-rerankqa-mistral-4b-v3/reranking',
    );
    expect(request.headers['authorization'], 'Bearer nvapi-test-000000');
    expect(http.body(0), fixtureJson('nvidia/rerank_request.json'));
    expect(scores.map((s) => s.id), ['m3', 'm1', 'm2']);
    expect(scores.first.score, closeTo(4.746, 1e-3));
  });

  test('builds the endpoint from the model id', () {
    expect(
      nvidiaRerankUrl('nvidia/llama-3.2-nv-rerankqa-1b-v2').toString(),
      'https://ai.api.nvidia.com/v1/retrieval/nvidia/llama-3_2-nv-rerankqa-1b-v2/reranking',
    );
    expect(
      nvidiaRerankUrl('nvidia/nv-rerankqa-mistral-4b-v3').toString(),
      'https://ai.api.nvidia.com/v1/retrieval/nvidia/'
      'nv-rerankqa-mistral-4b-v3/reranking',
    );
  });

  test('candidates missing from the response go last', () async {
    http.reply({
      'rankings': [
        {'index': 1, 'logit': 0.5},
      ],
    });
    final scores = await service('nvidia/nv-rerankqa-mistral-4b-v3')
        .rerank('q', candidates);
    expect(scores.map((s) => s.id), ['m2', 'm1', 'm3']);
    expect(scores[1].score, lessThan(scores[0].score));
  });

  test('no candidates means no request', () async {
    expect(
      await service('nvidia/nv-rerankqa-mistral-4b-v3').rerank('q', const []),
      isEmpty,
    );
    expect(http.requests, isEmpty);
  });

  test('HTTP errors are mapped', () async {
    http.reply({'detail': 'Unauthorized'}, status: 401);
    await expectLater(
      service('nvidia/nv-rerankqa-mistral-4b-v3').rerank('q', candidates),
      throwsA(isA<AiConfigurationException>()),
    );
  });
}
