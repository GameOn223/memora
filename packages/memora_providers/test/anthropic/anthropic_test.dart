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

VisionRequest _visionRequest({
  Uint8List? bytes,
  String mimeType = 'image/png',
}) => VisionRequest(
  imageBytes: bytes ?? _png,
  mimeType: mimeType,
  takenAt: DateTime(2026, 9, 1),
);

void main() {
  late ScriptedHttp http;

  setUp(() => http = ScriptedHttp());

  AnthropicClient client({String? apiKey = 'sk-ant-test-0000000000'}) =>
      AnthropicClient(
        ProviderConfig(
          providerId: 'anthropic',
          apiKey: apiKey,
          baseUrl: anthropicDescriptor.defaultBaseUrl,
        ),
        httpClient: http.client,
      );

  test('descriptor', () {
    expect(anthropicDescriptor.id, 'anthropic');
    expect(anthropicDescriptor.displayName, 'Anthropic');
    expect(anthropicDescriptor.location, ProviderLocation.cloud);
    expect(anthropicDescriptor.requiresApiKey, isTrue);
    expect(anthropicDescriptor.apiKeyHint, 'sk-ant-...');
    expect(anthropicDescriptor.defaultBaseUrl, 'https://api.anthropic.com/v1');
    expect(anthropicDescriptor.capabilities, {
      Capability.vision,
      Capability.chat,
    });
    for (final capability in [Capability.vision, Capability.chat]) {
      expect(anthropicDescriptor.suggestedModels[capability], [
        'claude-sonnet-5',
        'claude-haiku-4-5',
      ]);
    }
    expect(client().embeddings('x'), isNull);
    expect(client().reranker('x'), isNull);
  });

  group('vision', () {
    test('forces the record_memory tool and reads its input', () async {
      http.replyFixture('anthropic/vision_response.json');

      final u = await client()
          .vision('claude-sonnet-5')!
          .analyze(_visionRequest());

      final request = http.requests.single;
      expect(request.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(request.headers['x-api-key'], 'sk-ant-test-0000000000');
      expect(request.headers['anthropic-version'], '2023-06-01');
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(
        http.body(0),
        fixtureJsonWith('anthropic/vision_request.json', {
          '<analyze_instructions>': VisionPrompts.analyzeInstructions(
            _visionRequest(),
          ),
          '<schema>': VisionPrompts.understandingSchema,
        }),
      );
      expect(http.body(0).containsKey('temperature'), isFalse);

      expect(u.summary, 'Swiggy order receipt from Meghana Foods');
      expect(u.category, 'receipt');
      expect(u.entities, hasLength(2));
      expect(u.amounts.single.value, 702);
      expect(u.attributes.single.type, 'order_number');
    });

    test(
      'models that refuse forced tools get auto and an instruction',
      () async {
        http.replyFixture('anthropic/vision_response.json');

        await client().vision('claude-fable-5-1')!.analyze(_visionRequest());

        final body = http.body(0);
        expect(body['tool_choice'], {'type': 'auto'});
        final content =
            ((body['messages']! as List).single! as Map)['content']! as List;
        expect((content.last! as Map)['text'], contains('record_memory'));
      },
    );

    test('falls back to JSON in text when no tool was called', () async {
      http.reply({
        'type': 'message',
        'role': 'assistant',
        'content': [
          {
            'type': 'text',
            'text': '```json\n{"summary": "Map of Indiranagar", "category": "map"}\n```',
          },
        ],
        'stop_reason': 'end_turn',
      });
      final u = await client()
          .vision('claude-fable-5-1')!
          .analyze(_visionRequest());
      expect(u.category, 'map');
    });

    test('a refusal is a content error', () async {
      http.replyFixture('anthropic/vision_response_refusal.json');
      await expectLater(
        client().vision('claude-sonnet-5')!.analyze(_visionRequest()),
        throwsA(
          isA<AiContentException>().having(
            (e) => e.providerId,
            'providerId',
            'anthropic',
          ),
        ),
      );
    });

    test('rejects images Anthropic does not accept before sending', () async {
      await expectLater(
        client()
            .vision('claude-sonnet-5')!
            .analyze(_visionRequest(mimeType: 'image/heic')),
        throwsA(isA<AiContentException>()),
      );
      await expectLater(
        client()
            .vision('claude-sonnet-5')!
            .analyze(_visionRequest(bytes: Uint8List(5 * 1024 * 1024 + 1))),
        throwsA(isA<AiContentException>()),
      );
      expect(http.requests, isEmpty);
    });

    test('verify forces record_verification', () async {
      http.reply({
        'type': 'message',
        'role': 'assistant',
        'content': [
          {
            'type': 'tool_use',
            'id': 'toolu_v',
            'name': 'record_verification',
            'input': {'confirmed': false, 'observed_value': '₹720'},
          },
        ],
        'stop_reason': 'tool_use',
      });
      final request = VerificationRequest(
        imageBytes: _png,
        mimeType: 'image/png',
        attributeType: 'amount',
        expectedValue: '₹702',
      );

      final result = await client().vision('claude-haiku-4-5')!.verify(request);

      final body = http.body(0);
      expect(body['system'], VisionPrompts.verifyInstructions(request));
      expect(body['tool_choice'], {
        'type': 'tool',
        'name': 'record_verification',
      });
      expect(
        ((body['tools']! as List).single! as Map)['input_schema'],
        VisionPrompts.verificationSchema,
      );
      expect(result.confirmed, isFalse);
      expect(result.observedValue, '₹720');
    });

    test('overloaded is transient', () async {
      http.reply({
        'type': 'error',
        'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
      }, status: 529);
      await expectLater(
        client().vision('claude-sonnet-5')!.analyze(_visionRequest()),
        throwsA(isA<AiTransientException>()),
      );
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

    test(
      'maps the transcript and merges tool results into one user turn',
      () async {
        http.replyFixture('anthropic/chat_response_text.json');

        final turn = await client()
            .chat('claude-haiku-4-5')!
            .complete(
              const ChatRequest(
                system: 'You answer questions about saved memories.',
                tools: tools,
                temperature: 0.7,
                entries: [
                  UserEntry('Which food order cost the most?'),
                  AssistantEntry(
                    text: 'Let me search.',
                    toolCalls: [
                      ToolCall(
                        id: 'toolu_1',
                        name: 'search_memories',
                        arguments: {'text': 'food order'},
                      ),
                      ToolCall(
                        id: 'toolu_2',
                        name: 'search_by_date',
                        arguments: {'from': '2026-09-01'},
                      ),
                    ],
                  ),
                  ToolResultEntry(
                    callId: 'toolu_1',
                    toolName: 'search_memories',
                    content: '{"result_set_id":"rs1","count":4}',
                  ),
                  ToolResultEntry(
                    callId: 'toolu_2',
                    toolName: 'search_by_date',
                    content: '{"error":"to is required"}',
                    isError: true,
                  ),
                  UserEntry('Only Swiggy, please.'),
                ],
              ),
            );

        expect(http.body(0), fixtureJson('anthropic/chat_request_tools.json'));
        expect(
          turn.text,
          'Your priciest Swiggy order was ₹702 from Meghana Foods [[m:m7]].',
        );
        expect(turn.stopReason, ChatStopReason.endTurn);
      },
    );

    test('reads tool calls and replays thinking blocks unchanged', () async {
      http.replyFixture('anthropic/chat_response_tool_use.json');
      final chat = client().chat('claude-sonnet-5')!;

      final turn = await chat.complete(
        const ChatRequest(
          system: '',
          entries: [UserEntry('max?')],
          tools: tools,
        ),
      );

      expect(http.body(0).containsKey('system'), isFalse);
      expect(turn.stopReason, ChatStopReason.toolUse);
      expect(turn.text, "I'll find the highest amount.");
      expect(turn.toolCalls.map((c) => c.id), [
        'toolu_01Xk2m9aggr',
        'toolu_01Yq7p1getm',
      ]);
      expect(turn.toolCalls.first.arguments, {
        'attribute': 'amount',
        'op': 'max',
      });

      http.replyFixture('anthropic/chat_response_text.json');
      await chat.complete(
        ChatRequest(
          system: '',
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
      final response =
          fixtureJson('anthropic/chat_response_tool_use.json')! as Map;
      expect(messages[1], {
        'role': 'assistant',
        'content': response['content'],
      });
      expect(messages[2], {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': 'toolu_01Xk2m9aggr',
            'content': '{}',
          },
          {
            'type': 'tool_result',
            'tool_use_id': 'toolu_01Yq7p1getm',
            'content': '{}',
          },
        ],
      });
    });

    test('starts the transcript at the first user turn', () async {
      http.replyFixture('anthropic/chat_response_text.json');

      await client()
          .chat('claude-haiku-4-5')!
          .complete(
            const ChatRequest(
              system: '',
              entries: [
                AssistantEntry(
                  toolCalls: [
                    ToolCall(
                      id: 'toolu_old',
                      name: 'search_memories',
                      arguments: {},
                    ),
                  ],
                ),
                ToolResultEntry(
                  callId: 'toolu_old',
                  toolName: 'search_memories',
                  content: '{}',
                ),
                UserEntry('And the cheapest?'),
              ],
            ),
          );

      expect(http.body(0)['messages'], [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'And the cheapest?'},
          ],
        },
      ]);
    });

    test('maps stop reasons', () async {
      for (final (reason, expected) in [
        ('end_turn', ChatStopReason.endTurn),
        ('stop_sequence', ChatStopReason.endTurn),
        ('max_tokens', ChatStopReason.maxTokens),
        ('refusal', ChatStopReason.other),
        ('pause_turn', ChatStopReason.other),
      ]) {
        http.reply({
          'type': 'message',
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': 'x'},
          ],
          'stop_reason': reason,
        });
        final turn = await client()
            .chat('claude-haiku-4-5')!
            .complete(
              const ChatRequest(system: '', entries: [UserEntry('hi')]),
            );
        expect(turn.stopReason, expected, reason: reason);
      }
    });
  });

  group('models and connection', () {
    test('lists models in the order Anthropic returns them', () async {
      http.replyFixture('anthropic/models_response.json');
      expect(await client().listModels(Capability.chat), [
        'claude-sonnet-5',
        'claude-opus-5',
        'claude-haiku-4-5',
      ]);
      expect(
        http.requests.single.url.toString(),
        'https://api.anthropic.com/v1/models?limit=1000',
      );
      expect(await client().listModels(Capability.embeddings), isEmpty);
    });

    test('falls back to suggestions on failure', () async {
      http.reply({
        'type': 'error',
        'error': {
          'type': 'authentication_error',
          'message': 'invalid x-api-key',
        },
      }, status: 401);
      expect(await client().listModels(Capability.vision), [
        'claude-sonnet-5',
        'claude-haiku-4-5',
      ]);
    });

    test('testConnection', () async {
      http.replyFixture('anthropic/models_response.json');
      final ok = await client().testConnection();
      expect(ok.ok, isTrue);
      expect(ok.detail, '3 models available');

      http.reply({
        'type': 'error',
        'error': {
          'type': 'authentication_error',
          'message': 'invalid x-api-key',
        },
      }, status: 401);
      final failed = await client().testConnection();
      expect(failed.ok, isFalse);
      expect(failed.detail, 'The API key was rejected');

      expect((await client(apiKey: '').testConnection()).ok, isFalse);
    });
  });
}
