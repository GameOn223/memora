import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

import '../fakes/fake_stores.dart';

class _Vision implements VisionService {
  _Vision(this.model);

  final String model;

  @override
  Future<MemoryUnderstanding> analyze(VisionRequest request) =>
      throw UnimplementedError();

  @override
  Future<VerificationResult> verify(VerificationRequest request) =>
      throw UnimplementedError();
}

class _Client implements ProviderClient {
  _Client(this.descriptor, this.config);

  @override
  final ProviderDescriptor descriptor;
  final ProviderConfig config;

  @override
  VisionService? vision(String modelId) =>
      descriptor.supports(Capability.vision) ? _Vision(modelId) : null;

  @override
  ChatService? chat(String modelId) => null;

  @override
  EmbeddingService? embeddings(String modelId) => null;

  @override
  RerankService? reranker(String modelId) => null;

  @override
  Future<List<String>> listModels(Capability capability) async => const [];

  @override
  Future<ConnectionCheck> testConnection() async => const ConnectionCheck.ok();
}

const _cloud = ProviderDescriptor(
  id: 'nvidia',
  displayName: 'NVIDIA',
  location: ProviderLocation.cloud,
  capabilities: {Capability.vision, Capability.chat},
  requiresApiKey: true,
  defaultBaseUrl: 'https://integrate.api.nvidia.com/v1',
);

const _ollama = ProviderDescriptor(
  id: 'ollama',
  displayName: 'Ollama',
  location: ProviderLocation.selfHosted,
  capabilities: {Capability.vision, Capability.chat},
  defaultBaseUrl: 'http://localhost:11434/v1',
  baseUrlEditable: true,
);

const _local = ProviderDescriptor(
  id: 'local',
  displayName: 'On this device',
  location: ProviderLocation.onDevice,
  capabilities: {
    Capability.vision,
    Capability.embeddings,
    Capability.reranking,
  },
);

void main() {
  late ProviderRegistry registry;
  late InMemorySettingsStore settings;
  late InMemorySecretStore secrets;
  late CapabilityRouter router;
  final created = <ProviderConfig>[];

  setUp(() {
    created.clear();
    registry = ProviderRegistry();
    for (final d in [_cloud, _ollama, _local]) {
      registry.register(d, (config) {
        created.add(config);
        return _Client(d, config);
      });
    }
    settings = InMemorySettingsStore();
    secrets = InMemorySecretStore();
    router = CapabilityRouter(
      registry: registry,
      settings: AiSettingsRepository(settings),
      secrets: secrets,
    );
  });

  Future<void> select(
    Capability c,
    String provider,
    String model, {
    bool localOnly = false,
    Map<String, String> baseUrls = const {},
  }) async {
    final repo = AiSettingsRepository(settings);
    final current = await repo.load();
    await repo.save(
      current.copyWith(
        selections: {
          ...current.selections,
          c: CapabilitySelection(provider, model),
        },
        baseUrls: {...current.baseUrls, ...baseUrls},
        localOnly: localOnly,
      ),
    );
  }

  test('reports notConfigured when nothing is selected', () async {
    await expectLater(
      router.vision(),
      throwsA(
        isA<CapabilityUnavailableException>().having(
          (e) => e.reason,
          'reason',
          UnavailableReason.notConfigured,
        ),
      ),
    );
  });

  test('returns the selected service with provider and model', () async {
    await select(Capability.vision, 'nvidia', 'nemotron-vl');
    await secrets.write(CapabilityRouter.apiKeyName('nvidia'), 'nvapi-123');

    final resolved = await router.vision();

    expect(resolved.provider.id, 'nvidia');
    expect(resolved.modelId, 'nemotron-vl');
    expect((resolved.service as _Vision).model, 'nemotron-vl');
    expect(created.single.apiKey, 'nvapi-123');
    expect(created.single.baseUrl, 'https://integrate.api.nvidia.com/v1');
  });

  test('requires an API key when the provider needs one', () async {
    await select(Capability.vision, 'nvidia', 'nemotron-vl');
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

  test('local-only mode refuses cloud providers', () async {
    await select(Capability.vision, 'nvidia', 'nemotron-vl', localOnly: true);
    await secrets.write(CapabilityRouter.apiKeyName('nvidia'), 'nvapi-123');
    await expectLater(
      router.vision(),
      throwsA(
        isA<CapabilityUnavailableException>()
            .having(
              (e) => e.reason,
              'reason',
              UnavailableReason.blockedByLocalOnly,
            )
            .having((e) => e.providerName, 'providerName', 'NVIDIA'),
      ),
    );
    expect(
      created,
      isEmpty,
      reason: 'no client may be built for a blocked provider',
    );
  });

  test('local-only mode allows a LAN server but not a public one', () async {
    await select(
      Capability.vision,
      'ollama',
      'llava',
      localOnly: true,
      baseUrls: {'ollama': 'http://192.168.1.20:11434/v1'},
    );
    expect((await router.vision()).provider.id, 'ollama');
    expect(created.single.baseUrl, 'http://192.168.1.20:11434/v1');

    await select(
      Capability.vision,
      'ollama',
      'llava',
      localOnly: true,
      baseUrls: {'ollama': 'https://ollama.example.com/v1'},
    );
    await expectLater(
      router.vision(),
      throwsA(isA<CapabilityUnavailableException>()),
    );
  });

  test('status describes every capability without throwing', () async {
    await select(Capability.vision, 'local', 'ocr-rules');
    final statuses = await router.statuses();
    expect(statuses[Capability.vision]!.available, isTrue);
    expect(statuses[Capability.vision]!.provider!.id, 'local');
    expect(statuses[Capability.chat]!.available, isFalse);
    expect(statuses[Capability.chat]!.reason, UnavailableReason.notConfigured);
  });

  test('offDeviceProviders lists selected network providers once', () async {
    await select(Capability.vision, 'nvidia', 'a');
    await select(Capability.chat, 'nvidia', 'b');
    await select(Capability.embeddings, 'local', 'bge');
    final providers = await router.offDeviceProviders();
    expect(providers.map((p) => p.id), ['nvidia']);
  });

  test('unsupported capability is reported', () async {
    await select(Capability.chat, 'local', 'x');
    await expectLater(
      router.chat(),
      throwsA(
        isA<CapabilityUnavailableException>().having(
          (e) => e.reason,
          'reason',
          UnavailableReason.unsupportedByProvider,
        ),
      ),
    );
  });
}
