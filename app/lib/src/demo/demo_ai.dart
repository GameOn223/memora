import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

/// Provider descriptors the demo registers. They mirror the shipped presets
/// closely enough for the settings screens to behave like the real app.
const demoProviderDescriptors = <ProviderDescriptor>[
  ProviderDescriptor(
    id: 'local',
    displayName: 'On this device',
    location: ProviderLocation.onDevice,
    capabilities: {
      Capability.vision,
      Capability.chat,
      Capability.embeddings,
      Capability.reranking,
    },
    suggestedModels: {
      Capability.vision: ['ocr-rules', 'gemma-3n-e2b-it-int4'],
      Capability.chat: ['gemma-3-1b-it-int4', 'gemma-3n-e2b-it-int4'],
      Capability.embeddings: ['bge-small-en-v1.5'],
      Capability.reranking: ['score-fusion'],
    },
  ),
  ProviderDescriptor(
    id: 'nvidia',
    displayName: 'NVIDIA',
    location: ProviderLocation.cloud,
    capabilities: {
      Capability.vision,
      Capability.chat,
      Capability.embeddings,
      Capability.reranking,
    },
    suggestedModels: {
      Capability.vision: [
        'nemotron-vl-3b',
        'meta/llama-3.2-11b-vision-instruct',
      ],
      Capability.chat: ['meta/llama-3.3-70b-instruct'],
      Capability.embeddings: ['nvidia/nv-embedqa-e5-v5'],
      Capability.reranking: ['nvidia/nv-rerankqa-mistral-4b-v3'],
    },
    requiresApiKey: true,
    defaultBaseUrl: 'https://integrate.api.nvidia.com/v1',
    apiKeyHint: 'nvapi-...',
    apiKeyUrl: 'https://build.nvidia.com/settings/api-keys',
    homepage: 'https://build.nvidia.com',
  ),
  ProviderDescriptor(
    id: 'groq',
    displayName: 'Groq',
    location: ProviderLocation.cloud,
    capabilities: {Capability.vision, Capability.chat},
    suggestedModels: {
      Capability.vision: ['meta-llama/llama-4-scout-17b-16e-instruct'],
      Capability.chat: ['llama-3.3-70b', 'llama-3.3-70b-versatile'],
    },
    requiresApiKey: true,
    defaultBaseUrl: 'https://api.groq.com/openai/v1',
    apiKeyHint: 'gsk_...',
    apiKeyUrl: 'https://console.groq.com/keys',
    homepage: 'https://console.groq.com',
  ),
  ProviderDescriptor(
    id: 'openai',
    displayName: 'OpenAI',
    location: ProviderLocation.cloud,
    capabilities: {Capability.vision, Capability.chat, Capability.embeddings},
    suggestedModels: {
      Capability.vision: ['gpt-5-mini', 'gpt-4.1-mini'],
      Capability.chat: ['gpt-5-mini', 'gpt-4.1-mini'],
      Capability.embeddings: ['text-embedding-3-small'],
    },
    requiresApiKey: true,
    defaultBaseUrl: 'https://api.openai.com/v1',
    apiKeyHint: 'sk-...',
    apiKeyUrl: 'https://platform.openai.com/api-keys',
    homepage: 'https://platform.openai.com',
  ),
  ProviderDescriptor(
    id: 'gemini',
    displayName: 'Google Gemini',
    location: ProviderLocation.cloud,
    capabilities: {Capability.vision, Capability.chat, Capability.embeddings},
    suggestedModels: {
      Capability.vision: ['gemini-2.5-flash', 'gemini-2.5-flash-lite'],
      Capability.chat: ['gemini-2.5-flash', 'gemini-2.5-flash-lite'],
      Capability.embeddings: ['gemini-embedding-001'],
    },
    requiresApiKey: true,
    defaultBaseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    apiKeyHint: 'AIza...',
    apiKeyUrl: 'https://aistudio.google.com/apikey',
    homepage: 'https://aistudio.google.com',
  ),
  ProviderDescriptor(
    id: 'anthropic',
    displayName: 'Anthropic',
    location: ProviderLocation.cloud,
    capabilities: {Capability.vision, Capability.chat},
    suggestedModels: {
      Capability.vision: ['claude-sonnet-4-5', 'claude-haiku-4-5'],
      Capability.chat: ['claude-sonnet-4-5', 'claude-haiku-4-5'],
    },
    requiresApiKey: true,
    defaultBaseUrl: 'https://api.anthropic.com/v1',
    apiKeyHint: 'sk-ant-...',
    apiKeyUrl: 'https://platform.claude.com/settings/keys',
    homepage: 'https://console.anthropic.com',
  ),
  ProviderDescriptor(
    id: 'ollama',
    displayName: 'Ollama',
    location: ProviderLocation.selfHosted,
    capabilities: {Capability.vision, Capability.chat, Capability.embeddings},
    suggestedModels: {
      Capability.vision: ['qwen2.5vl', 'llava'],
      Capability.chat: ['llama3.2'],
      Capability.embeddings: ['nomic-embed-text'],
    },
    defaultBaseUrl: 'http://localhost:11434/v1',
    baseUrlEditable: true,
    homepage: 'https://ollama.com',
  ),
];

/// [installed] names the on-device model files the demo pretends to hold,
/// which decides whether the local provider can serve chat.
ProviderRegistry buildDemoRegistry({Set<String> Function()? installed}) {
  final registry = ProviderRegistry();
  for (final descriptor in demoProviderDescriptors) {
    registry.register(
      descriptor,
      (config) => DemoProviderClient(descriptor, config, installed: installed),
    );
  }
  return registry;
}

/// A provider client that answers from canned data and never touches the
/// network.
class DemoProviderClient implements ProviderClient {
  DemoProviderClient(this.descriptor, this.config, {this.installed});

  /// On-device model files the demo holds, for [isModelReady].
  final Set<String> Function()? installed;

  @override
  final ProviderDescriptor descriptor;
  final ProviderConfig config;

  @override
  Future<bool> isModelReady(Capability capability, String modelId) async {
    if (!modelId.startsWith('gemma')) return true;
    return installed?.call().contains(modelId) ?? false;
  }

  @override
  VisionService? vision(String modelId) =>
      descriptor.supports(Capability.vision) ? const _DemoVision() : null;

  @override
  ChatService? chat(String modelId) =>
      descriptor.supports(Capability.chat) ? const _DemoChat() : null;

  @override
  EmbeddingService? embeddings(String modelId) =>
      descriptor.supports(Capability.embeddings)
      ? _DemoEmbeddings(descriptor.id, modelId)
      : null;

  @override
  RerankService? reranker(String modelId) =>
      descriptor.supports(Capability.reranking) ? const _DemoRerank() : null;

  @override
  Future<List<String>> listModels(Capability capability) async {
    final suggested = descriptor.suggestedModels[capability] ?? const [];
    return [...suggested];
  }

  @override
  Future<ConnectionCheck> testConnection() async {
    if (descriptor.requiresApiKey && (config.apiKey ?? '').isEmpty) {
      return const ConnectionCheck.failed('Add an API key first.');
    }
    if (descriptor.location == ProviderLocation.onDevice) {
      return const ConnectionCheck.ok(detail: 'Runs on this phone.');
    }
    final count = descriptor.suggestedModels.values.fold(
      0,
      (n, list) => n + list.length,
    );
    return ConnectionCheck.ok(detail: '${count + 9} models available');
  }
}

class _DemoVision implements VisionService {
  const _DemoVision();

  @override
  Future<MemoryUnderstanding> analyze(VisionRequest request) async =>
      const MemoryUnderstanding(summary: 'Image', category: 'other');

  @override
  Future<VerificationResult> verify(VerificationRequest request) async =>
      const VerificationResult(confirmed: true);
}

class _DemoChat implements ChatService {
  const _DemoChat();

  @override
  Future<ChatTurn> complete(ChatRequest request) async => const ChatTurn(
    text: '',
    toolCalls: [],
    stopReason: ChatStopReason.endTurn,
  );
}

class _DemoEmbeddings implements EmbeddingService {
  _DemoEmbeddings(this.provider, this.modelId);

  final String provider;
  final String modelId;

  @override
  EmbeddingModelInfo get model => EmbeddingModelInfo(
    provider: provider,
    modelId: modelId,
    version: '1',
    dimensions: 384,
  );

  @override
  Future<List<Float32List>> embed(
    List<String> texts, {
    EmbeddingPurpose purpose = EmbeddingPurpose.document,
  }) async => [for (final _ in texts) Float32List(384)];
}

class _DemoRerank implements RerankService {
  const _DemoRerank();

  @override
  Future<List<RerankScore>> rerank(
    String query,
    List<RerankCandidate> candidates,
  ) async => [for (final c in candidates) RerankScore(c.id, c.priorScore)];
}
