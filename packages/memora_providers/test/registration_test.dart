import 'package:memora_core/memora_core.dart';
import 'package:memora_providers/memora_providers.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/scripted_http.dart';

void main() {
  late ProviderRegistry registry;
  late ScriptedHttp http;
  late FakeLocalLlmFiles llmFiles;

  setUp(() {
    http = ScriptedHttp();
    registry = ProviderRegistry();
    llmFiles = FakeLocalLlmFiles();
    registerBuiltInProviders(
      registry,
      httpClient: http.client,
      local: LocalRuntime(
        ocr: FakeOcrEngine(),
        embeddingRuntime: FakeEmbeddingRuntime(),
        modelFiles: FakeLocalModelFiles(),
        llm: ScriptedLlmRuntime(),
        llmFiles: llmFiles,
      ),
    );
  });

  test('registers every built-in provider, on-device first', () {
    expect(registry.descriptors.map((d) => d.id), [
      'local',
      'openai',
      'groq',
      'nvidia',
      'openrouter',
      'ollama',
      'lmstudio',
      'custom',
      'gemini',
      'anthropic',
    ]);
    expect(builtInProviderDescriptors, registry.descriptors);
  });

  test('every factory builds a client for its own descriptor', () {
    for (final descriptor in registry.descriptors) {
      final client = registry.create(
        ProviderConfig(
          providerId: descriptor.id,
          baseUrl: descriptor.defaultBaseUrl ?? 'http://192.168.1.9:8080/v1',
          apiKey: 'key-123456',
        ),
      );
      expect(client.descriptor.id, descriptor.id);
      for (final capability in Capability.values) {
        final model = descriptor.defaultModel(capability) ?? 'some-model';
        final service = switch (capability) {
          Capability.vision => client.vision(model),
          Capability.chat => client.chat(model),
          Capability.embeddings => client.embeddings(model),
          Capability.reranking => client.reranker(model),
        };
        expect(
          service != null,
          descriptor.supports(capability),
          reason: '${descriptor.id} ${capability.key}',
        );
      }
    }
  });

  group('with the capability router', () {
    late InMemorySettingsStore settings;
    late InMemorySecretStore secrets;
    late CapabilityRouter router;

    setUp(() {
      settings = InMemorySettingsStore();
      secrets = InMemorySecretStore();
      router = CapabilityRouter(
        registry: registry,
        settings: AiSettingsRepository(settings),
        secrets: secrets,
      );
    });

    Future<void> save(AiSettings value) =>
        AiSettingsRepository(settings).save(value);

    test('an on-device model answers chat in local-only mode', () async {
      llmFiles.install('gemma-3-1b-it-int4');
      await save(
        const AiSettings(
          localOnly: true,
          selections: {
            Capability.chat: CapabilitySelection('local', 'gemma-3-1b-it-int4'),
          },
        ),
      );

      final chat = await router.chat();

      expect(chat.provider.id, 'local');
      expect(chat.modelId, 'gemma-3-1b-it-int4');
      expect(chat.service, isA<LocalLlmChatService>());
      expect(http.requests, isEmpty);
    });

    test('the same model without its file is unavailable', () async {
      await save(
        const AiSettings(
          localOnly: true,
          selections: {
            Capability.chat: CapabilitySelection('local', 'gemma-3-1b-it-int4'),
          },
        ),
      );

      await expectLater(
        router.chat(),
        throwsA(
          isA<CapabilityUnavailableException>().having(
            (e) => e.reason,
            'reason',
            UnavailableReason.modelNotDownloaded,
          ),
        ),
      );
    });

    test('local-only mode allows on-device and LAN servers only', () async {
      await save(
        const AiSettings(
          localOnly: true,
          selections: {
            Capability.vision: CapabilitySelection('local', 'ocr-rules'),
            Capability.chat: CapabilitySelection('ollama', 'llama3.2'),
            Capability.embeddings: CapabilitySelection(
              'openai',
              'text-embedding-3-small',
            ),
            Capability.reranking: CapabilitySelection('local', 'score-fusion'),
          },
        ),
      );
      await secrets.write(
        CapabilityRouter.apiKeyName('openai'),
        'sk-test-000000',
      );

      expect((await router.vision()).service, isA<OcrVisionService>());
      expect((await router.chat()).provider.id, 'ollama');
      expect((await router.reranker()).service, isA<FusionReranker>());
      await expectLater(
        router.embeddings(),
        throwsA(
          isA<CapabilityUnavailableException>().having(
            (e) => e.reason,
            'reason',
            UnavailableReason.blockedByLocalOnly,
          ),
        ),
      );
    });

    test('a custom server gets its optional key', () async {
      await save(
        const AiSettings(
          selections: {Capability.chat: CapabilitySelection('custom', 'qwen3')},
          baseUrls: {'custom': 'http://10.0.0.8:8000/v1'},
        ),
      );
      await secrets.write(
        CapabilityRouter.apiKeyName('custom'),
        'token-abcdef',
      );
      http.replyFixture('openai/chat_response_text.json');

      final chat = (await router.chat()).service;
      await chat.complete(
        const ChatRequest(system: '', entries: [UserEntry('hi')]),
      );

      expect(
        http.requests.single.url.toString(),
        'http://10.0.0.8:8000/v1/chat/completions',
      );
      expect(
        http.requests.single.headers['authorization'],
        'Bearer token-abcdef',
      );
    });

    test('cloud providers need their key', () async {
      await save(
        const AiSettings(
          selections: {
            Capability.vision: CapabilitySelection(
              'anthropic',
              'claude-sonnet-5',
            ),
          },
        ),
      );
      await expectLater(
        router.vision(),
        throwsA(
          isA<CapabilityUnavailableException>().having(
            (e) => e.reason,
            'reason',
            UnavailableReason.missingApiKey,
          ),
        ),
      );
    });
  });
}
