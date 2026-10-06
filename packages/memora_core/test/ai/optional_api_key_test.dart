import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

import '../fakes/fake_stores.dart';

class _Chat implements ChatService {
  @override
  Future<ChatTurn> complete(ChatRequest request) => throw UnimplementedError();
}

class _Client with ModelsAlwaysReady implements ProviderClient {
  _Client(this.descriptor);

  @override
  final ProviderDescriptor descriptor;

  @override
  VisionService? vision(String modelId) => null;

  @override
  ChatService? chat(String modelId) => _Chat();

  @override
  EmbeddingService? embeddings(String modelId) => null;

  @override
  RerankService? reranker(String modelId) => null;

  @override
  Future<List<String>> listModels(Capability capability) async => const [];

  @override
  Future<ConnectionCheck> testConnection() async => const ConnectionCheck.ok();
}

const _custom = ProviderDescriptor(
  id: 'custom',
  displayName: 'Custom',
  location: ProviderLocation.selfHosted,
  capabilities: {Capability.chat},
  apiKeyOptional: true,
  baseUrlEditable: true,
);

const _noKey = ProviderDescriptor(
  id: 'plain',
  displayName: 'Plain',
  location: ProviderLocation.selfHosted,
  capabilities: {Capability.chat},
  defaultBaseUrl: 'http://localhost:1234/v1',
);

void main() {
  late InMemorySettingsStore settings;
  late InMemorySecretStore secrets;
  late CapabilityRouter router;
  final created = <ProviderConfig>[];

  setUp(() {
    created.clear();
    final registry = ProviderRegistry();
    for (final d in [_custom, _noKey]) {
      registry.register(d, (config) {
        created.add(config);
        return _Client(d);
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

  Future<void> select(String provider) => AiSettingsRepository(settings).save(
    AiSettings(
      selections: {Capability.chat: CapabilitySelection(provider, 'model')},
      baseUrls: {provider: 'http://10.0.0.2:8000/v1'},
    ),
  );

  test('descriptors default to not taking an optional key', () {
    expect(_noKey.apiKeyOptional, isFalse);
  });

  test('an optional key is passed along when saved', () async {
    await select('custom');
    await secrets.write(CapabilityRouter.apiKeyName('custom'), 'token-123');

    await router.chat();

    expect(created.single.apiKey, 'token-123');
  });

  test(
    'a missing optional key does not make the capability unavailable',
    () async {
      await select('custom');

      final resolved = await router.chat();

      expect(resolved.provider.id, 'custom');
      expect(created.single.apiKey, isNull);
    },
  );

  test('providers without a key never read one', () async {
    await select('plain');
    await secrets.write(CapabilityRouter.apiKeyName('plain'), 'leftover');

    await router.chat();

    expect(created.single.apiKey, isNull);
  });
}
