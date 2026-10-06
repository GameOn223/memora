import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

import 'fake_stores.dart';

/// Vision that replays scripted results. Each entry is a value to return or
/// an exception to throw.
class ScriptedVisionService implements VisionService {
  ScriptedVisionService({List<Object>? analyze, List<Object>? verify})
    : analyzeScript = [...?analyze],
      verifyScript = [...?verify];

  final List<Object> analyzeScript;
  final List<Object> verifyScript;
  final List<VisionRequest> analyzeRequests = [];
  final List<VerificationRequest> verifyRequests = [];

  @override
  Future<MemoryUnderstanding> analyze(VisionRequest request) async {
    analyzeRequests.add(request);
    if (analyzeScript.isEmpty) {
      throw StateError('No scripted analyze result left');
    }
    final next = analyzeScript.removeAt(0);
    if (next is MemoryUnderstanding) return next;
    throw next;
  }

  @override
  Future<VerificationResult> verify(VerificationRequest request) async {
    verifyRequests.add(request);
    if (verifyScript.isEmpty) {
      throw StateError('No scripted verify result left');
    }
    final next = verifyScript.removeAt(0);
    if (next is VerificationResult) return next;
    throw next;
  }
}

/// Chat that replays scripted turns and records every request.
class ScriptedChatService implements ChatService {
  ScriptedChatService(List<Object> script) : script = [...script];

  final List<Object> script;
  final List<ChatRequest> requests = [];

  @override
  Future<ChatTurn> complete(ChatRequest request) async {
    requests.add(request);
    if (script.isEmpty) throw StateError('No scripted chat turn left');
    final next = script.removeAt(0);
    if (next is ChatTurn) return next;
    throw next;
  }
}

ChatTurn toolTurn(List<ToolCall> calls, {String text = ''}) =>
    ChatTurn(text: text, toolCalls: calls, stopReason: ChatStopReason.toolUse);

ChatTurn answerTurn(String text) => ChatTurn(
  text: text,
  toolCalls: const [],
  stopReason: ChatStopReason.endTurn,
);

/// Bag-of-words embeddings hashed into a small vector. Texts sharing words
/// land close together, which is all retrieval tests need.
class FakeEmbeddingService implements EmbeddingService {
  FakeEmbeddingService({
    this.model = const EmbeddingModelInfo(
      provider: 'fake',
      modelId: 'bag-of-words',
      version: '1',
      dimensions: 64,
    ),
  });

  @override
  EmbeddingModelInfo model;

  /// Thrown by [embed] when set.
  Object? failWith;
  final List<List<String>> calls = [];
  final List<EmbeddingPurpose> purposes = [];

  @override
  Future<List<Float32List>> embed(
    List<String> texts, {
    EmbeddingPurpose purpose = EmbeddingPurpose.document,
  }) async {
    calls.add(texts);
    purposes.add(purpose);
    if (failWith case final error?) throw error;
    return [for (final text in texts) vectorFor(text, model.dimensions)];
  }

  static Float32List vectorFor(String text, int dimensions) {
    final vector = Float32List(dimensions);
    for (final token in searchTokens(text)) {
      var hash = 0;
      for (final unit in token.codeUnits) {
        hash = (hash * 31 + unit) & 0x7fffffff;
      }
      vector[hash % dimensions] += 1;
    }
    var norm = 0.0;
    for (final v in vector) {
      norm += v * v;
    }
    if (norm == 0) {
      vector[0] = 1;
      return vector;
    }
    final length = _sqrt(norm);
    for (var i = 0; i < dimensions; i++) {
      vector[i] = vector[i] / length;
    }
    return vector;
  }

  static double _sqrt(double x) {
    var guess = x;
    for (var i = 0; i < 30; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }
}

/// Reranker that reverses whatever order it was given, so tests can tell it
/// ran.
class ReversingReranker implements RerankService {
  final List<String> queries = [];

  @override
  Future<List<RerankScore>> rerank(
    String query,
    List<RerankCandidate> candidates,
  ) async {
    queries.add(query);
    return [
      for (var i = 0; i < candidates.length; i++)
        RerankScore(candidates[i].id, i.toDouble()),
    ].reversed.toList();
  }
}

class _HarnessClient with ModelsAlwaysReady implements ProviderClient {
  _HarnessClient(this.descriptor, this.harness);

  @override
  final ProviderDescriptor descriptor;
  final AiHarness harness;

  @override
  VisionService? vision(String modelId) => harness.vision;

  @override
  ChatService? chat(String modelId) => harness.chat;

  @override
  EmbeddingService? embeddings(String modelId) => harness.embeddings;

  @override
  RerankService? reranker(String modelId) => harness.reranker;

  @override
  Future<List<String>> listModels(Capability capability) async => const [];

  @override
  Future<ConnectionCheck> testConnection() async => const ConnectionCheck.ok();
}

/// A real [CapabilityRouter] over one fake provider whose services can be
/// swapped during a test.
class AiHarness {
  AiHarness._({
    required this.descriptor,
    this.vision,
    this.chat,
    this.embeddings,
    this.reranker,
  }) {
    registry.register(descriptor, (_) => _HarnessClient(descriptor, this));
    router = CapabilityRouter(
      registry: registry,
      settings: aiSettings,
      secrets: secrets,
    );
  }

  /// Builds the harness and selects every capability that has a service.
  static Future<AiHarness> create({
    VisionService? vision,
    ChatService? chat,
    EmbeddingService? embeddings,
    RerankService? reranker,
    ProviderLocation location = ProviderLocation.onDevice,
    bool requiresApiKey = false,
    String? apiKey,
    bool localOnly = false,
    String providerId = 'fake',
    String displayName = 'Fake AI',
  }) async {
    final harness = AiHarness._(
      descriptor: ProviderDescriptor(
        id: providerId,
        displayName: displayName,
        location: location,
        capabilities: Capability.values.toSet(),
        requiresApiKey: requiresApiKey,
        defaultBaseUrl: location == ProviderLocation.onDevice
            ? null
            : 'https://api.example.com/v1',
      ),
      vision: vision,
      chat: chat,
      embeddings: embeddings,
      reranker: reranker,
    );
    if (apiKey != null) {
      await harness.secrets.write(
        CapabilityRouter.apiKeyName(providerId),
        apiKey,
      );
    }
    final selections = {
      if (vision != null) Capability.vision: 'vision-model',
      if (chat != null) Capability.chat: 'chat-model',
      if (embeddings != null) Capability.embeddings: 'embedding-model',
      if (reranker != null) Capability.reranking: 'rerank-model',
    };
    await harness.aiSettings.save(
      AiSettings(
        localOnly: localOnly,
        selections: {
          for (final e in selections.entries)
            e.key: CapabilitySelection(providerId, e.value),
        },
      ),
    );
    return harness;
  }

  final ProviderDescriptor descriptor;
  VisionService? vision;
  ChatService? chat;
  EmbeddingService? embeddings;
  RerankService? reranker;

  final registry = ProviderRegistry();
  final settingsStore = InMemorySettingsStore();
  final secrets = InMemorySecretStore();
  late final AiSettingsRepository aiSettings = AiSettingsRepository(
    settingsStore,
  );
  late final CapabilityRouter router;

  Future<void> update(AiSettings Function(AiSettings current) change) async {
    await aiSettings.save(change(await aiSettings.load()));
  }

  Future<void> unselect(Capability capability) =>
      update((s) => s.withoutSelection(capability));
}
