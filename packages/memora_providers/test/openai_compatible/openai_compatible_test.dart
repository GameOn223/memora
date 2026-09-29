import 'dart:convert';
import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';
import 'package:memora_providers/memora_providers.dart';
import 'package:test/test.dart';

import '../support/scripted_http.dart';

final _png = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
]);

VisionRequest _visionRequest() => VisionRequest(
  imageBytes: _png,
  mimeType: 'image/png',
  takenAt: DateTime(2026, 9, 1),
);

void main() {
  late ScriptedHttp http;

  setUp(() => http = ScriptedHttp());

  OpenAiCompatibleClient clientFor(
    ProviderDescriptor descriptor, {
    String? apiKey = 'sk-test-0000000000',
    String? baseUrl,
  }) {
    return OpenAiCompatibleClient(
      descriptor,
      ProviderConfig(
        providerId: descriptor.id,
        apiKey: apiKey,
        baseUrl: baseUrl ?? descriptor.defaultBaseUrl,
      ),
      httpClient: http.client,
    );
  }

  group('presets', () {
    test('describe every OpenAI-compatible preset', () {
      final byId = {for (final d in openAiCompatibleDescriptors) d.id: d};
      expect(byId.keys, [
        'openai',
        'groq',
        'nvidia',
        'openrouter',
        'ollama',
        'lmstudio',
        'custom',
      ]);

      expect(openAiDescriptor.location, ProviderLocation.cloud);
      expect(openAiDescriptor.requiresApiKey, isTrue);
      expect(openAiDescriptor.apiKeyHint, 'sk-...');
      expect(openAiDescriptor.defaultBaseUrl, 'https://api.openai.com/v1');
      expect(
        openAiDescriptor.defaultModel(Capability.vision),
        openAiVisionModels.first,
      );
      expect(
        openAiDescriptor.suggestedModels[Capability.chat],
        openAiChatModels,
      );
      expect(
        openAiDescriptor.defaultModel(Capability.embeddings),
        'text-embedding-3-small',
      );

      expect(groqDescriptor.defaultBaseUrl, 'https://api.groq.com/openai/v1');
      expect(groqDescriptor.capabilities, {Capability.vision, Capability.chat});
      expect(
        groqDescriptor.defaultModel(Capability.vision),
        groqVisionModels.first,
      );
      expect(
        groqDescriptor.defaultModel(Capability.chat),
        groqChatModels.first,
      );

      expect(nvidiaDescriptor.capabilities, Capability.values.toSet());
      expect(
        nvidiaDescriptor.defaultBaseUrl,
        'https://integrate.api.nvidia.com/v1',
      );
      expect(
        nvidiaDescriptor.defaultModel(Capability.reranking),
        'nvidia/nv-rerankqa-mistral-4b-v3',
      );
      expect(
        nvidiaDescriptor.defaultModel(Capability.embeddings),
        'nvidia/nv-embedqa-e5-v5',
      );

      expect(
        openRouterDescriptor.defaultBaseUrl,
        'https://openrouter.ai/api/v1',
      );
      expect(openRouterDescriptor.capabilities, {
        Capability.vision,
        Capability.chat,
      });

      for (final d in [
        ollamaDescriptor,
        lmStudioDescriptor,
        customOpenAiDescriptor,
      ]) {
        expect(d.location, ProviderLocation.selfHosted, reason: d.id);
        expect(d.requiresApiKey, isFalse, reason: d.id);
        expect(d.apiKeyOptional, isTrue, reason: d.id);
        expect(d.baseUrlEditable, isTrue, reason: d.id);
        expect(d.capabilities, {
          Capability.vision,
          Capability.chat,
          Capability.embeddings,
        }, reason: d.id);
      }
      expect(ollamaDescriptor.defaultBaseUrl, 'http://localhost:11434/v1');
      expect(ollamaDescriptor.suggestedModels[Capability.vision], [
        'qwen2.5vl',
        'llava',
      ]);
      expect(
        ollamaDescriptor.defaultModel(Capability.embeddings),
        'nomic-embed-text',
      );
      expect(lmStudioDescriptor.defaultBaseUrl, 'http://localhost:1234/v1');
      expect(customOpenAiDescriptor.defaultBaseUrl, isNull);

      for (final d in [
        openAiDescriptor,
        groqDescriptor,
        nvidiaDescriptor,
        openRouterDescriptor,
      ]) {
        expect(d.location, ProviderLocation.cloud, reason: d.id);
        expect(d.requiresApiKey, isTrue, reason: d.id);
        expect(d.baseUrlEditable, isFalse, reason: d.id);
      }
    });

    test('hands out only the services a preset supports', () {
      final groq = clientFor(groqDescriptor);
      expect(groq.vision('m'), isNotNull);
      expect(groq.chat('m'), isNotNull);
      expect(groq.embeddings('m'), isNull);
      expect(groq.reranker('m'), isNull);

      final nvidia = clientFor(nvidiaDescriptor);
      expect(nvidia.embeddings('m'), isNotNull);
      expect(nvidia.reranker('m'), isA<NvidiaRerankService>());

      expect(clientFor(ollamaDescriptor).reranker('m'), isNull);
    });
  });

  group('vision', () {
    test('OpenAI gets a json_schema request and parses the answer', () async {
      http.replyFixture('openai/vision_response.json');
      final vision = clientFor(openAiDescriptor).vision('gpt-4.1-mini')!;

      final u = await vision.analyze(_visionRequest());

      final request = http.requests.single;
      expect(
        request.url.toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(request.headers['authorization'], 'Bearer sk-test-0000000000');
      expect(
        http.body(0),
        fixtureJsonWith('openai/vision_request_openai.json', {
          '<analyze_instructions>': VisionPrompts.analyzeInstructions(
            _visionRequest(),
          ),
          '<closed_schema>': fixtureJson(
            'openai/understanding_schema_closed.json',
          ),
        }),
      );

      expect(u.summary, 'Reliance electricity bill for August 2026');
      expect(u.category, 'utility_bill');
      expect(u.extractedText, contains('Amount due Rs 1,842'));
      expect(u.amounts.single.value, 1842);
      expect(u.amounts.single.currency, 'INR');
      expect(u.dates.single.value, '2026-08-31');
      expect(u.attributes.single.value, '•••• 4471');
      expect(u.confidence, 0.86);
    });

    test('reasoning models get no temperature', () async {
      http.replyFixture('openai/vision_response.json');
      await clientFor(openAiDescriptor)
          .vision('gpt-5-mini')!
          .analyze(_visionRequest());
      expect(http.body(0).containsKey('temperature'), isFalse);
      expect(http.body(0)['max_completion_tokens'], 16000);
    });

    test('Groq gets json_object and fenced JSON still parses', () async {
      http.replyFixture('openai/vision_response_fenced.json');
      final vision = clientFor(groqDescriptor)
          .vision('meta-llama/llama-4-scout-17b-16e-instruct')!;

      final u = await vision.analyze(_visionRequest());

      expect(
        http.body(0),
        fixtureJsonWith('openai/vision_request_groq.json', {
          '<analyze_instructions>': VisionPrompts.analyzeInstructions(
            _visionRequest(),
          ),
        }),
      );
      expect(u.summary, 'IndiGo boarding pass BLR to DEL');
      expect(u.attributes.single.value, 'K7Q2XZ');
    });

    test(
      'retries once without response_format when the text is not JSON',
      () async {
        http.reply(_completion('I think this is a bill.'));
        http.replyFixture('openai/vision_response.json');

        final u = await clientFor(
          ollamaDescriptor,
          apiKey: null,
        ).vision('qwen2.5vl')!.analyze(_visionRequest());

        expect(http.requests, hasLength(2));
        expect(http.body(0)['response_format'], {'type': 'json_object'});
        expect(http.body(1).containsKey('response_format'), isFalse);
        expect(
          http.requests.first.headers.containsKey('authorization'),
          isFalse,
        );
        expect(u.category, 'utility_bill');
      },
    );

    test(
      'retries without response_format when the server rejects it',
      () async {
        http.reply({
          'error': {'message': "'response_format.type' must be 'json_schema'"},
        }, status: 400);
        http.replyFixture('openai/vision_response.json');

        await clientFor(
          customOpenAiDescriptor,
          baseUrl: 'http://192.168.1.5:8000/v1/',
        ).vision('any')!.analyze(_visionRequest());

        expect(http.requests, hasLength(2));
        expect(
          http.requests.first.url.toString(),
          'http://192.168.1.5:8000/v1/chat/completions',
        );
        expect(http.body(1).containsKey('response_format'), isFalse);
      },
    );

    test('gives up with a content error after the retry', () async {
      http.reply(_completion('no json here'));
      http.reply(_completion('still none'));
      await expectLater(
        clientFor(groqDescriptor).vision('m')!.analyze(_visionRequest()),
        throwsA(
          isA<AiContentException>().having(
            (e) => e.providerId,
            'providerId',
            'groq',
          ),
        ),
      );
    });

    test('a refusal is a content error', () async {
      http.reply({
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': null,
              'refusal': "I can't help with that.",
            },
            'finish_reason': 'stop',
          },
        ],
      });
      await expectLater(
        clientFor(openAiDescriptor)
            .vision('gpt-4.1-mini')!
            .analyze(_visionRequest()),
        throwsA(isA<AiContentException>()),
      );
      expect(http.requests, hasLength(1));
    });

    test('an error object inside a 200 response is mapped', () async {
      http.reply({
        'error': {'message': 'Provider returned error', 'code': 429},
      });
      await expectLater(
        clientFor(openRouterDescriptor)
            .vision('google/gemini-2.5-flash')!
            .analyze(_visionRequest()),
        throwsA(isA<AiTransientException>()),
      );
    });

    test('custom preset without a base URL is a configuration error', () async {
      final client = OpenAiCompatibleClient(
        customOpenAiDescriptor,
        const ProviderConfig(providerId: 'custom'),
        httpClient: http.client,
      );
      await expectLater(
        client.vision('m')!.analyze(_visionRequest()),
        throwsA(isA<AiConfigurationException>()),
      );
      expect(http.requests, isEmpty);
    });

    test('verify sends the narrow question and reads the answer', () async {
      http.reply(
        _completion('{"confirmed": false, "observed_value": "₹2,130"}'),
      );
      final request = VerificationRequest(
        imageBytes: _png,
        mimeType: 'image/png',
        attributeType: 'amount',
        expectedValue: '₹2,103',
      );

      final result = await clientFor(openAiDescriptor)
          .vision('gpt-4.1-mini')!
          .verify(request);

      final body = http.body(0);
      final messages = body['messages']! as List<Object?>;
      expect(
        (messages.first! as Map)['content'],
        VisionPrompts.verifyInstructions(request),
      );
      final format = body['response_format']! as Map;
      expect((format['json_schema']! as Map)['name'], 'verification_result');
      expect(result.confirmed, isFalse);
      expect(result.observedValue, '₹2,130');
    });
  });

  group('chat', () {
    const tools = [
      ToolDefinition(
        name: 'search_memories',
        description: 'Hybrid search over memories.',
        parameters: {
          'type': 'object',
          'properties': {
            'text': {'type': 'string'},
          },
          'required': ['text'],
        },
      ),
    ];

    test('maps the transcript and tools into the request', () async {
      http.replyFixture('openai/chat_response_text.json');
      final chat = clientFor(openAiDescriptor).chat('gpt-4.1-mini')!;

      final turn = await chat.complete(
        const ChatRequest(
          system: 'You answer questions about saved memories.',
          tools: tools,
          entries: [
            UserEntry('Which electricity bill was highest?'),
            AssistantEntry(
              toolCalls: [
                ToolCall(
                  id: 'call_1',
                  name: 'search_memories',
                  arguments: {'text': 'electricity bill'},
                ),
              ],
            ),
            ToolResultEntry(
              callId: 'call_1',
              toolName: 'search_memories',
              content: '{"result_set_id":"rs1","count":3}',
            ),
            AssistantEntry(text: 'Checking the amounts.'),
            UserEntry('Only this year.'),
          ],
        ),
      );

      expect(http.body(0), fixtureJson('openai/chat_request_tools.json'));
      expect(
        turn.text,
        'Your highest electricity bill was ₹2,103 in July [[m:m1]].',
      );
      expect(turn.toolCalls, isEmpty);
      expect(turn.stopReason, ChatStopReason.endTurn);
    });

    test('other presets send max_tokens', () async {
      http.replyFixture('openai/chat_response_text.json');
      await clientFor(groqDescriptor)
          .chat('llama-3.3-70b-versatile')!
          .complete(
            const ChatRequest(
              system: '',
              entries: [UserEntry('hi')],
              maxOutputTokens: 300,
            ),
          );
      final body = http.body(0);
      expect(body['max_tokens'], 300);
      expect(body.containsKey('max_completion_tokens'), isFalse);
      expect(body.containsKey('tools'), isFalse);
      expect(body['messages'], [
        {'role': 'user', 'content': 'hi'},
      ]);
    });

    test('reasoning models get room to think and no temperature', () async {
      http.replyFixture('openai/chat_response_text.json');
      await clientFor(openAiDescriptor)
          .chat('gpt-5-mini')!
          .complete(const ChatRequest(system: 's', entries: [UserEntry('hi')]));
      final body = http.body(0);
      expect(body.containsKey('temperature'), isFalse);
      expect(body['max_completion_tokens'], greaterThan(1024));
    });

    test('parses tool calls leniently and round-trips them', () async {
      http.replyFixture('openai/chat_response_tool_calls.json');
      final chat = clientFor(openAiDescriptor).chat('gpt-4.1-mini')!;

      final turn = await chat.complete(
        const ChatRequest(
          system: 's',
          entries: [UserEntry('max?')],
          tools: tools,
        ),
      );

      expect(turn.stopReason, ChatStopReason.toolUse);
      expect(turn.text, '');
      expect(turn.toolCalls.map((c) => c.id), ['call_Xk2m9', 'call_Yq7p1']);
      expect(turn.toolCalls.first.name, 'aggregate_results');
      expect(turn.toolCalls.first.arguments, {
        'attribute': 'amount',
        'op': 'max',
      });
      expect(turn.toolCalls.last.arguments, isEmpty);

      http.replyFixture('openai/chat_response_text.json');
      await chat.complete(
        ChatRequest(
          system: 's',
          tools: tools,
          entries: [
            const UserEntry('max?'),
            AssistantEntry(text: turn.text, toolCalls: turn.toolCalls),
            for (final call in turn.toolCalls)
              ToolResultEntry(
                callId: call.id,
                toolName: call.name,
                content: '{}',
              ),
          ],
        ),
      );

      final messages = http.body(1)['messages']! as List<Object?>;
      final assistant = messages[2]! as Map;
      final calls = assistant['tool_calls']! as List<Object?>;
      final first = calls.first! as Map;
      expect(first['id'], 'call_Xk2m9');
      expect(jsonDecode((first['function']! as Map)['arguments']! as String), {
        'attribute': 'amount',
        'op': 'max',
      });
      expect((messages[3]! as Map)['tool_call_id'], 'call_Xk2m9');
      expect((messages[4]! as Map)['tool_call_id'], 'call_Yq7p1');
    });

    test('drops tool results whose call fell out of the window', () async {
      http.replyFixture('openai/chat_response_text.json');

      await clientFor(groqDescriptor)
          .chat('llama-3.3-70b-versatile')!
          .complete(
            const ChatRequest(
              system: '',
              entries: [
                ToolResultEntry(
                  callId: 'call_old',
                  toolName: 'search_memories',
                  content: '{}',
                ),
                UserEntry('And the cheapest?'),
              ],
            ),
          );

      expect(http.body(0)['messages'], [
        {'role': 'user', 'content': 'And the cheapest?'},
      ]);
    });

    test('maps finish reasons', () async {
      for (final (reason, expected) in [
        ('stop', ChatStopReason.endTurn),
        ('length', ChatStopReason.maxTokens),
        ('content_filter', ChatStopReason.other),
      ]) {
        http.reply(_completion('x', finishReason: reason));
        final turn = await clientFor(groqDescriptor)
            .chat('m')!
            .complete(
              const ChatRequest(system: '', entries: [UserEntry('hi')]),
            );
        expect(turn.stopReason, expected, reason: reason);
      }
    });

    test(
      'sends OpenRouter reasoning details back with the tool calls',
      () async {
        http.replyFixture('openai/chat_response_openrouter_reasoning.json');
        final chat = clientFor(openRouterDescriptor)
            .chat('google/gemini-3-flash')!;
        final turn = await chat.complete(
          const ChatRequest(
            system: 's',
            entries: [UserEntry('bills')],
            tools: tools,
          ),
        );
        expect(turn.toolCalls.single.id, 'tool_search_memories_Zx81');

        http.replyFixture('openai/chat_response_text.json');
        await chat.complete(
          ChatRequest(
            system: 's',
            tools: tools,
            entries: [
              const UserEntry('bills'),
              AssistantEntry(toolCalls: turn.toolCalls),
              ToolResultEntry(
                callId: turn.toolCalls.single.id,
                toolName: 'search_memories',
                content: '{}',
              ),
            ],
          ),
        );
        final messages = http.body(1)['messages']! as List<Object?>;
        expect((messages[2]! as Map)['reasoning_details'], [
          {
            'type': 'reasoning.encrypted',
            'data': 'CiQB0e2Kb3sig',
            'id': 'tool_search_memories_Zx81',
            'format': 'google-gemini-v1',
            'index': 0,
          },
        ]);
      },
    );
  });

  group('embeddings', () {
    test('orders by index, normalizes and learns dimensions', () async {
      http.replyFixture('openai/embeddings_response.json');
      final service = clientFor(
        ollamaDescriptor,
        apiKey: null,
      ).embeddings('mxbai-embed-large-test')!;

      final vectors = await service.embed(['first', 'second']);

      expect(http.body(0), {
        'model': 'mxbai-embed-large-test',
        'input': ['first', 'second'],
      });
      expect(http.requests.single.url.path, '/v1/embeddings');
      expect(vectors[0][0], closeTo(0.6, 1e-6));
      expect(vectors[0][2], closeTo(0.8, 1e-6));
      expect(vectors[1][1], closeTo(1, 1e-6));
      expect(
        service.model,
        const EmbeddingModelInfo(
          provider: 'ollama',
          modelId: 'mxbai-embed-large-test',
          version: '1',
          dimensions: 3,
        ),
      );
      expect(
        clientFor(
          ollamaDescriptor,
          apiKey: null,
        ).embeddings('mxbai-embed-large-test')!.model.dimensions,
        3,
        reason: 'learned dimensions are shared by later services',
      );
    });

    test('knows dimensions of common models before the first call', () {
      expect(
        clientFor(openAiDescriptor)
            .embeddings('text-embedding-3-small')!
            .model
            .dimensions,
        1536,
      );
      expect(
        clientFor(openAiDescriptor)
            .embeddings('text-embedding-3-large')!
            .model
            .dimensions,
        3072,
      );
      expect(
        clientFor(nvidiaDescriptor)
            .embeddings('nvidia/nv-embedqa-e5-v5')!
            .model
            .dimensions,
        1024,
      );
      expect(
        clientFor(ollamaDescriptor)
            .embeddings('nomic-embed-text')!
            .model
            .dimensions,
        768,
      );
      expect(
        clientFor(ollamaDescriptor)
            .embeddings('nomic-embed-text:latest')!
            .model
            .dimensions,
        768,
      );
      expect(
        clientFor(openAiDescriptor)
            .embeddings('text-embedding-3-small')!
            .model
            .storageId,
        'openai/text-embedding-3-small',
      );
    });

    test('NVIDIA gets input_type and float encoding', () async {
      http.reply({
        'object': 'list',
        'data': [
          {
            'index': 0,
            'embedding': [1, 1],
            'object': 'embedding',
          },
        ],
        'model': 'nvidia/nv-embedqa-e5-v5',
      });
      await clientFor(nvidiaDescriptor)
          .embeddings('nvidia/nv-embedqa-e5-v5')!
          .embed([
            'electricity bills over 2000',
          ], purpose: EmbeddingPurpose.query);
      expect(http.body(0), fixtureJson('nvidia/embeddings_request.json'));

      http.reply({
        'data': [
          {
            'index': 0,
            'embedding': [1, 1],
          },
        ],
      });
      await clientFor(nvidiaDescriptor)
          .embeddings('nvidia/nv-embedqa-e5-v5')!
          .embed(['doc']);
      expect(http.body(1)['input_type'], 'passage');
    });

    test('resolveModel probes once for an unknown model', () async {
      http.reply({
        'data': [
          {
            'index': 0,
            'embedding': [1, 0, 0, 0, 1],
          },
        ],
      });
      final service =
          clientFor(
                ollamaDescriptor,
                apiKey: null,
              ).embeddings('some-private-model')!
              as OpenAiEmbeddingService;

      expect(service.model.dimensions, 0, reason: 'nothing known yet');

      final info = await service.resolveModel();

      expect(info.dimensions, 5);
      expect(service.model.dimensions, 5);
      expect(http.requests, hasLength(1));
      expect(http.body(0)['input']! as List, hasLength(1));

      // A second call answers from the cache.
      expect((await service.resolveModel()).dimensions, 5);
      expect(http.requests, hasLength(1));
    });

    test('resolveModel does not call a provider it already knows', () async {
      final service =
          clientFor(openAiDescriptor).embeddings('text-embedding-3-small')!
              as OpenAiEmbeddingService;
      expect((await service.resolveModel()).dimensions, 1536);
      expect(http.requests, isEmpty);
    });

    test('an Ollama tag does not split the embedding space', () async {
      http.reply({
        'data': [
          {
            'index': 0,
            'embedding': [0, 1],
          },
        ],
      });
      final tagged = clientFor(
        ollamaDescriptor,
        apiKey: null,
      ).embeddings('nomic-embed-text:latest')!;

      expect(tagged.model.storageId, 'ollama/nomic-embed-text');
      expect(tagged.model.dimensions, 768);

      await tagged.embed(['bill']);
      expect(http.body(0)['model'], 'nomic-embed-text:latest');
    });

    test('empty input makes no request', () async {
      expect(
        await clientFor(openAiDescriptor)
            .embeddings('text-embedding-3-small')!
            .embed([]),
        isEmpty,
      );
      expect(http.requests, isEmpty);
    });

    test('a short response is an error', () async {
      http.reply({
        'data': [
          {
            'index': 0,
            'embedding': [1, 0],
          },
        ],
      });
      await expectLater(
        clientFor(openAiDescriptor)
            .embeddings('text-embedding-3-small')!
            .embed(['a', 'b']),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('models and connection', () {
    test('lists models sorted, split by capability', () async {
      http.replyFixture('openai/models_response.json');
      http.replyFixture('openai/models_response.json');
      final client = clientFor(openAiDescriptor);

      expect(await client.listModels(Capability.chat), [
        'gpt-4.1-mini',
        'gpt-5-mini',
      ]);
      expect(await client.listModels(Capability.embeddings), [
        'text-embedding-3-large',
        'text-embedding-3-small',
      ]);
      expect(
        http.requests.first.url.toString(),
        'https://api.openai.com/v1/models',
      );
    });

    test('a server with no embedding model offers none', () async {
      http.reply({
        'data': [
          {'id': 'llama3.2'},
          {'id': 'qwen2.5vl'},
        ],
      });
      expect(
        await clientFor(
          ollamaDescriptor,
          apiKey: null,
        ).listModels(Capability.embeddings),
        ollamaEmbeddingModels,
        reason: 'the suggestions, never the chat models',
      );
    });

    test('OpenRouter vision lists only image models', () async {
      http.replyFixture('openai/models_response_openrouter.json');
      expect(
        await clientFor(openRouterDescriptor).listModels(Capability.vision),
        ['google/gemini-2.5-flash', 'openai/gpt-5-mini'],
      );
    });

    test('falls back to suggestions when listing fails', () async {
      http.reply({'error': 'down'}, status: 503);
      expect(
        await clientFor(groqDescriptor).listModels(Capability.vision),
        groqDescriptor.suggestedModels[Capability.vision],
      );
      expect(
        await clientFor(nvidiaDescriptor).listModels(Capability.reranking),
        ['nvidia/nv-rerankqa-mistral-4b-v3'],
      );
      expect(
        await clientFor(groqDescriptor).listModels(Capability.embeddings),
        isEmpty,
      );
    });

    test('testConnection reports the model count or the problem', () async {
      http.replyFixture('openai/models_response.json');
      final ok = await clientFor(openAiDescriptor).testConnection();
      expect(ok.ok, isTrue);
      expect(ok.detail, '4 models available');

      http.reply({
        'error': {'message': 'bad key'},
      }, status: 401);
      final failed = await clientFor(openAiDescriptor).testConnection();
      expect(failed.ok, isFalse);
      expect(failed.detail, 'The API key was rejected');

      final missingKey = await clientFor(
        groqDescriptor,
        apiKey: '',
      ).testConnection();
      expect(missingKey.ok, isFalse);

      final noUrl = await OpenAiCompatibleClient(
        customOpenAiDescriptor,
        const ProviderConfig(providerId: 'custom'),
        httpClient: http.client,
      ).testConnection();
      expect(noUrl.ok, isFalse);
      expect(http.requests, hasLength(2));
    });
  });
}

Map<String, Object?> _completion(
  String content, {
  String finishReason = 'stop',
}) => {
  'id': 'chatcmpl-test',
  'object': 'chat.completion',
  'choices': [
    {
      'index': 0,
      'message': {'role': 'assistant', 'content': content},
      'finish_reason': finishReason,
    },
  ],
};
