import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';
import 'package:memora_providers/memora_providers.dart';
import 'package:memora_providers/src/gemini/schema.dart';
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

VisionRequest _visionRequest({String mimeType = 'image/png'}) => VisionRequest(
  imageBytes: _png,
  mimeType: mimeType,
  takenAt: DateTime(2026, 9, 1),
);

const _base = 'https://generativelanguage.googleapis.com/v1beta';

void main() {
  late ScriptedHttp http;

  setUp(() => http = ScriptedHttp());

  GeminiClient client({String? apiKey = 'AIzaTestKey000000000000000'}) =>
      GeminiClient(
        ProviderConfig(
          providerId: 'gemini',
          apiKey: apiKey,
          baseUrl: geminiDescriptor.defaultBaseUrl,
        ),
        httpClient: http.client,
      );

  test('descriptor', () {
    expect(geminiDescriptor.id, 'gemini');
    expect(geminiDescriptor.location, ProviderLocation.cloud);
    expect(geminiDescriptor.requiresApiKey, isTrue);
    expect(geminiDescriptor.defaultBaseUrl, _base);
    expect(geminiDescriptor.capabilities, {
      Capability.vision,
      Capability.chat,
      Capability.embeddings,
    });
    expect(
      geminiDescriptor.suggestedModels[Capability.vision],
      geminiVisionModels,
    );
    expect(
      geminiDescriptor.suggestedModels[Capability.chat],
      geminiVisionModels,
    );
    expect(
      geminiDescriptor.defaultModel(Capability.embeddings),
      geminiEmbeddingModels.first,
    );
    expect(
      geminiRequestedDimensions,
      containsPair(geminiEmbeddingModels.first, 768),
    );
    expect(client().reranker('x'), isNull);
    expect(client().descriptor, same(geminiDescriptor));
  });

  group('schema conversion', () {
    test(
      'turns nullable type lists into nullable and drops unsupported keys',
      () {
        expect(geminiSchema(VisionPrompts.verificationSchema), {
          'type': 'object',
          'properties': {
            'confirmed': {'type': 'boolean'},
            'observed_value': {'type': 'string', 'nullable': true},
          },
          'required': ['confirmed', 'observed_value'],
        });
        expect(
          geminiSchema({
            r'$schema': 'x',
            'type': 'object',
            'additionalProperties': false,
            'properties': {
              'n': {
                'type': ['integer', 'string'],
                'const': 'x',
              },
              'list': {
                'type': 'array',
                'items': {
                  'type': 'string',
                  'enum': ['a', 'b'],
                },
              },
            },
          }),
          {
            'type': 'object',
            'properties': {
              'n': {
                'anyOf': [
                  {'type': 'integer'},
                  {'type': 'string'},
                ],
              },
              'list': {
                'type': 'array',
                'items': {
                  'type': 'string',
                  'enum': ['a', 'b'],
                },
              },
            },
          },
        );
      },
    );

    test('the understanding schema passes through unchanged', () {
      expect(
        geminiSchema(VisionPrompts.understandingSchema),
        VisionPrompts.understandingSchema,
      );
    });
  });

  group('vision', () {
    test('sends inline image data with a response schema', () async {
      http.replyFixture('gemini/vision_response.json');

      final u = await client()
          .vision('gemini-2.5-flash')!
          .analyze(_visionRequest());

      final request = http.requests.single;
      expect(
        request.url.toString(),
        '$_base/models/gemini-2.5-flash:generateContent',
      );
      expect(request.headers['x-goog-api-key'], 'AIzaTestKey000000000000000');
      expect(
        request.url.query,
        isEmpty,
        reason: 'the key never goes in the URL',
      );
      expect(
        http.body(0),
        fixtureJsonWith('gemini/vision_request.json', {
          '<analyze_instructions>': VisionPrompts.analyzeInstructions(
            _visionRequest(),
          ),
          '<schema>': VisionPrompts.understandingSchema,
        }),
      );
      expect(u.summary, 'Airtel postpaid bill for August 2026');
      expect(u.amounts.single.value, 799);
      expect(u.dates.single.type, 'due_date');
    });

    test('accepts a models/ prefix on the model id', () async {
      http.replyFixture('gemini/vision_response.json');
      await client()
          .vision('models/gemini-2.5-flash')!
          .analyze(_visionRequest());
      expect(
        http.requests.single.url.path,
        '/v1beta/models/gemini-2.5-flash:generateContent',
      );
    });

    test('a safety stop is a content error', () async {
      http.replyFixture('gemini/vision_response_safety.json');
      await expectLater(
        client().vision('gemini-2.5-flash')!.analyze(_visionRequest()),
        throwsA(
          isA<AiContentException>().having(
            (e) => e.providerId,
            'providerId',
            'gemini',
          ),
        ),
      );
    });

    test('a blocked prompt is a content error', () async {
      http.reply({
        'promptFeedback': {'blockReason': 'PROHIBITED_CONTENT'},
      });
      await expectLater(
        client().vision('gemini-2.5-flash')!.analyze(_visionRequest()),
        throwsA(isA<AiContentException>()),
      );
    });

    test('HEIC is accepted, PDF is not', () async {
      http.replyFixture('gemini/vision_response.json');
      await client()
          .vision('gemini-2.5-flash')!
          .analyze(_visionRequest(mimeType: 'image/heic'));
      await expectLater(
        client()
            .vision('gemini-2.5-flash')!
            .analyze(_visionRequest(mimeType: 'image/tiff')),
        throwsA(isA<AiContentException>()),
      );
    });

    test('verify uses the converted verification schema', () async {
      http.reply({
        'candidates': [
          {
            'content': {
              'role': 'model',
              'parts': [
                {'text': '{"confirmed": true, "observed_value": null}'},
              ],
            },
            'finishReason': 'STOP',
          },
        ],
      });
      final request = VerificationRequest(
        imageBytes: _png,
        mimeType: 'image/png',
        attributeType: 'amount',
        expectedValue: '₹799',
      );

      final result = await client().vision('gemini-2.5-flash')!.verify(request);

      final body = http.body(0);
      expect(((body['systemInstruction']! as Map)['parts']! as List).single, {
        'text': VisionPrompts.verifyInstructions(request),
      });
      expect(
        (body['generationConfig']! as Map)['responseSchema'],
        geminiSchema(VisionPrompts.verificationSchema),
      );
      expect(result.confirmed, isTrue);
      expect(result.observedValue, isNull);
    });
  });

  group('chat', () {
    const tools = [
      ToolDefinition(
        name: 'search_memories',
        description: 'Hybrid search over memories.',
        parameters: {
          'type': 'object',
          'additionalProperties': false,
          'properties': {
            'text': {'type': 'string', 'description': 'Words to look for'},
            'currency': {
              'type': ['string', 'null'],
            },
          },
          'required': ['text'],
        },
      ),
      ToolDefinition(
        name: 'list_categories',
        description: 'Lists categories.',
        parameters: {'type': 'object', 'properties': <String, Object?>{}},
      ),
    ];

    test('maps transcript, tool results and declarations', () async {
      http.replyFixture('gemini/chat_response_text.json');

      final turn = await client()
          .chat('gemini-2.5-flash')!
          .complete(
            const ChatRequest(
              system: 'You answer questions about saved memories.',
              tools: tools,
              entries: [
                UserEntry('Which bill was highest?'),
                AssistantEntry(
                  text: 'Searching.',
                  toolCalls: [
                    ToolCall(
                      id: 'c1',
                      name: 'search_memories',
                      arguments: {'text': 'bill'},
                    ),
                    ToolCall(
                      id: 'c2',
                      name: 'search_by_date',
                      arguments: {'from': '2026-01-01'},
                    ),
                  ],
                ),
                ToolResultEntry(
                  callId: 'c1',
                  toolName: 'search_memories',
                  content: '{"result_set_id":"rs1","count":2}',
                ),
                ToolResultEntry(
                  callId: 'c2',
                  toolName: 'search_by_date',
                  content: 'from must be before to',
                  isError: true,
                ),
              ],
            ),
          );

      expect(
        http.requests.single.url.toString(),
        '$_base/models/gemini-2.5-flash:generateContent',
      );
      expect(http.body(0), fixtureJson('gemini/chat_request_tools.json'));
      expect(turn.text, 'Your highest bill was ₹2,103 in July [[m:m1]].');
      expect(turn.stopReason, ChatStopReason.endTurn);
      expect(turn.toolCalls, isEmpty);
    });

    test('reads function calls and replays signatures and ids', () async {
      http.replyFixture('gemini/chat_response_function_call.json');
      final chat = client().chat('gemini-3-flash')!;

      final turn = await chat.complete(
        const ChatRequest(
          system: '',
          entries: [UserEntry('max?')],
          tools: tools,
        ),
      );

      expect(turn.stopReason, ChatStopReason.toolUse);
      expect(turn.toolCalls, hasLength(2));
      expect(turn.toolCalls[0].id, '8f2b1a3c');
      expect(turn.toolCalls[0].name, 'aggregate_results');
      expect(turn.toolCalls[0].arguments, {'attribute': 'amount', 'op': 'max'});
      expect(turn.toolCalls[1].id, startsWith('call_'));
      expect(turn.toolCalls[1].arguments, {'id': 'm1'});
      expect(http.body(0).containsKey('systemInstruction'), isFalse);

      http.replyFixture('gemini/chat_response_text.json');
      await chat.complete(
        ChatRequest(
          system: '',
          tools: tools,
          entries: [
            const UserEntry('max?'),
            AssistantEntry(toolCalls: turn.toolCalls),
            for (final call in turn.toolCalls)
              ToolResultEntry(
                callId: call.id,
                toolName: call.name,
                content: '{"v": 1}',
              ),
          ],
        ),
      );

      final contents = http.body(1)['contents']! as List<Object?>;
      expect(contents[1], {
        'role': 'model',
        'parts': [
          {
            'functionCall': {
              'id': '8f2b1a3c',
              'name': 'aggregate_results',
              'args': {'attribute': 'amount', 'op': 'max'},
            },
            'thoughtSignature': 'CiwBjz1rX7sigA',
          },
          {
            'functionCall': {
              'name': 'get_memory',
              'args': {'id': 'm1'},
            },
          },
        ],
      });
      expect(contents[2], {
        'role': 'user',
        'parts': [
          {
            'functionResponse': {
              'id': '8f2b1a3c',
              'name': 'aggregate_results',
              'response': {
                'content': {'v': 1},
              },
            },
          },
          {
            'functionResponse': {
              'name': 'get_memory',
              'response': {
                'content': {'v': 1},
              },
            },
          },
        ],
      });
    });

    test('starts the transcript at the first user turn', () async {
      http.replyFixture('gemini/chat_response_text.json');

      await client()
          .chat('gemini-2.5-flash')!
          .complete(
            const ChatRequest(
              system: '',
              entries: [
                AssistantEntry(text: 'Earlier answer.'),
                UserEntry('And the cheapest?'),
              ],
            ),
          );

      expect(http.body(0)['contents'], [
        {
          'role': 'user',
          'parts': [
            {'text': 'And the cheapest?'},
          ],
        },
      ]);
    });

    test('maps finish reasons', () async {
      for (final (reason, expected) in [
        ('STOP', ChatStopReason.endTurn),
        ('MAX_TOKENS', ChatStopReason.maxTokens),
        ('SAFETY', ChatStopReason.other),
      ]) {
        http.reply({
          'candidates': [
            {
              'content': {
                'role': 'model',
                'parts': [
                  {'text': 'x'},
                ],
              },
              'finishReason': reason,
            },
          ],
        });
        final turn = await client()
            .chat('gemini-2.5-flash')!
            .complete(
              const ChatRequest(system: '', entries: [UserEntry('hi')]),
            );
        expect(turn.stopReason, expected, reason: reason);
      }
    });

    test('thought parts are not part of the answer', () async {
      http.reply({
        'candidates': [
          {
            'content': {
              'role': 'model',
              'parts': [
                {'text': 'thinking about it', 'thought': true},
                {'text': 'Answer.'},
              ],
            },
            'finishReason': 'STOP',
          },
        ],
      });
      final turn = await client()
          .chat('gemini-2.5-flash')!
          .complete(const ChatRequest(system: '', entries: [UserEntry('hi')]));
      expect(turn.text, 'Answer.');
    });
  });

  group('embeddings', () {
    test('batches requests with task type and 768 dimensions', () async {
      http.replyFixture('gemini/embeddings_response.json');
      final service = client().embeddings('gemini-embedding-001')!;

      expect(
        service.model,
        const EmbeddingModelInfo(
          provider: 'gemini',
          modelId: 'gemini-embedding-001',
          version: '1',
          dimensions: 768,
        ),
      );

      final vectors = await service.embed([
        'Airtel bill',
        'IndiGo boarding pass',
      ]);

      expect(
        http.requests.single.url.toString(),
        '$_base/models/gemini-embedding-001:batchEmbedContents',
      );
      expect(http.body(0), fixtureJson('gemini/embeddings_request.json'));
      expect(vectors[0][0], closeTo(0.6, 1e-6));
      expect(vectors[1][1], closeTo(1, 1e-6));
    });

    test('queries use RETRIEVAL_QUERY', () async {
      http.reply({
        'embeddings': [
          {
            'values': [1, 0],
          },
        ],
      });
      await client().embeddings('text-embedding-004')!.embed([
        'bills',
      ], purpose: EmbeddingPurpose.query);
      final request = (http.body(0)['requests']! as List).single! as Map;
      expect(request['taskType'], 'RETRIEVAL_QUERY');
      expect(request.containsKey('outputDimensionality'), isFalse);
    });

    test('a count mismatch is an error', () async {
      http.reply({'embeddings': <Object?>[]});
      await expectLater(
        client().embeddings('gemini-embedding-001')!.embed(['a']),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('models and connection', () {
    test('lists models across pages, filtered by method', () async {
      http.replyFixture('gemini/models_response.json');
      http.replyFixture('gemini/models_response_page2.json');

      final chat = await client().listModels(Capability.chat);

      expect(chat, [
        'gemini-2.5-flash',
        'gemini-2.5-flash-lite',
        'gemini-3-flash',
      ]);
      expect(http.requests[0].url.toString(), '$_base/models?pageSize=1000');
      expect(
        http.requests[1].url.toString(),
        '$_base/models?pageSize=1000&pageToken=Chdtb2RlbHMvZ2VtaW5pLTIuNS1wcm8',
      );

      http.replyFixture('gemini/models_response.json');
      http.replyFixture('gemini/models_response_page2.json');
      expect(await client().listModels(Capability.embeddings), [
        'gemini-embedding-001',
        'text-embedding-004',
      ]);
    });

    test('falls back to suggestions on failure', () async {
      http.reply({
        'error': {
          'code': 400,
          'message': 'API key not valid.',
          'status': 'INVALID_ARGUMENT',
        },
      }, status: 400);
      expect(
        await client().listModels(Capability.vision),
        geminiDescriptor.suggestedModels[Capability.vision],
      );
    });

    test('testConnection', () async {
      http.replyFixture('gemini/models_response.json');
      final ok = await client().testConnection();
      expect(ok.ok, isTrue);
      expect(ok.detail, contains('models available'));

      http.reply({
        'error': {
          'code': 403,
          'message': 'Permission denied',
          'status': 'PERMISSION_DENIED',
        },
      }, status: 403);
      expect((await client().testConnection()).ok, isFalse);

      expect((await client(apiKey: null).testConnection()).ok, isFalse);
    });
  });
}
