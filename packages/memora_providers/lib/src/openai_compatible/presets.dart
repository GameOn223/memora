import 'package:memora_core/memora_core.dart';

const openAiDescriptor = ProviderDescriptor(
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
  apiKeyHint: 'sk-...',
  defaultBaseUrl: 'https://api.openai.com/v1',
  homepage: 'https://platform.openai.com',
);

const groqDescriptor = ProviderDescriptor(
  id: 'groq',
  displayName: 'Groq',
  location: ProviderLocation.cloud,
  capabilities: {Capability.vision, Capability.chat},
  suggestedModels: {
    Capability.vision: ['meta-llama/llama-4-scout-17b-16e-instruct'],
    Capability.chat: ['llama-3.3-70b-versatile'],
  },
  requiresApiKey: true,
  apiKeyHint: 'gsk_...',
  defaultBaseUrl: 'https://api.groq.com/openai/v1',
  homepage: 'https://console.groq.com',
);

const nvidiaDescriptor = ProviderDescriptor(
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
    Capability.vision: ['meta/llama-3.2-11b-vision-instruct'],
    Capability.chat: ['meta/llama-3.3-70b-instruct'],
    Capability.embeddings: ['nvidia/nv-embedqa-e5-v5'],
    Capability.reranking: ['nvidia/nv-rerankqa-mistral-4b-v3'],
  },
  requiresApiKey: true,
  apiKeyHint: 'nvapi-...',
  defaultBaseUrl: 'https://integrate.api.nvidia.com/v1',
  homepage: 'https://build.nvidia.com',
);

const openRouterDescriptor = ProviderDescriptor(
  id: 'openrouter',
  displayName: 'OpenRouter',
  location: ProviderLocation.cloud,
  capabilities: {Capability.vision, Capability.chat},
  suggestedModels: {
    Capability.vision: ['google/gemini-2.5-flash', 'openai/gpt-5-mini'],
    Capability.chat: ['google/gemini-2.5-flash', 'openai/gpt-5-mini'],
  },
  requiresApiKey: true,
  apiKeyHint: 'sk-or-...',
  defaultBaseUrl: 'https://openrouter.ai/api/v1',
  homepage: 'https://openrouter.ai',
);

const ollamaDescriptor = ProviderDescriptor(
  id: 'ollama',
  displayName: 'Ollama',
  location: ProviderLocation.selfHosted,
  capabilities: {Capability.vision, Capability.chat, Capability.embeddings},
  suggestedModels: {
    Capability.vision: ['qwen2.5vl', 'llava'],
    Capability.chat: ['llama3.2'],
    Capability.embeddings: ['nomic-embed-text'],
  },
  apiKeyOptional: true,
  defaultBaseUrl: 'http://localhost:11434/v1',
  baseUrlEditable: true,
  homepage: 'https://ollama.com',
);

const lmStudioDescriptor = ProviderDescriptor(
  id: 'lmstudio',
  displayName: 'LM Studio',
  location: ProviderLocation.selfHosted,
  capabilities: {Capability.vision, Capability.chat, Capability.embeddings},
  apiKeyOptional: true,
  defaultBaseUrl: 'http://localhost:1234/v1',
  baseUrlEditable: true,
  homepage: 'https://lmstudio.ai',
);

/// Any server that speaks the OpenAI chat completions protocol. Treated as
/// self-hosted, so local-only mode decides by looking at the base URL.
const customOpenAiDescriptor = ProviderDescriptor(
  id: 'custom',
  displayName: 'Custom OpenAI-compatible server',
  location: ProviderLocation.selfHosted,
  capabilities: {Capability.vision, Capability.chat, Capability.embeddings},
  apiKeyOptional: true,
  baseUrlEditable: true,
);

const openAiCompatibleDescriptors = [
  openAiDescriptor,
  groqDescriptor,
  nvidiaDescriptor,
  openRouterDescriptor,
  ollamaDescriptor,
  lmStudioDescriptor,
  customOpenAiDescriptor,
];

/// How the adapter asks a server for JSON.
enum JsonResponseFormat {
  /// `response_format: {type: json_schema, ...}` with the full schema.
  jsonSchema,

  /// `response_format: {type: json_object}`, the older JSON mode.
  jsonObject,
}

/// Differences between servers that otherwise speak the same protocol.
class OpenAiCompatibleProfile {
  const OpenAiCompatibleProfile({
    this.responseFormat = JsonResponseFormat.jsonObject,
    this.useMaxCompletionTokens = false,
    this.embeddingInputType = false,
    this.visionMaxTokens = 4096,
  });

  factory OpenAiCompatibleProfile.forProvider(String providerId) {
    return switch (providerId) {
      'openai' => const OpenAiCompatibleProfile(
        responseFormat: JsonResponseFormat.jsonSchema,
        useMaxCompletionTokens: true,
        visionMaxTokens: 16000,
      ),
      // LM Studio documents json_schema only.
      'openrouter' || 'lmstudio' => const OpenAiCompatibleProfile(
        responseFormat: JsonResponseFormat.jsonSchema,
      ),
      'nvidia' => const OpenAiCompatibleProfile(embeddingInputType: true),
      _ => const OpenAiCompatibleProfile(),
    };
  }

  final JsonResponseFormat responseFormat;

  /// OpenAI replaced `max_tokens` with `max_completion_tokens`.
  final bool useMaxCompletionTokens;

  /// NVIDIA retrieval embeddings encode queries and passages differently.
  final bool embeddingInputType;

  /// Output limit for one image analysis.
  final int visionMaxTokens;

  String get maxTokensField =>
      useMaxCompletionTokens ? 'max_completion_tokens' : 'max_tokens';
}

final _reasoningModel = RegExp(r'^(gpt-5|o[1-9])');

/// OpenAI reasoning models, including when routed through OpenRouter as
/// `openai/...`. They reject any temperature other than the default.
bool isOpenAiReasoningModel(String modelId) =>
    _reasoningModel.hasMatch(modelId.split('/').last.toLowerCase());
