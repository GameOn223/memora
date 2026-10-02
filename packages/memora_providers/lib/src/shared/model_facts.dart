/// Facts about providers that go stale when a vendor ships or retires a
/// model. Everything version-dependent lives here, so there is one place to
/// check and one date to trust.
///
/// A suggested model is what a user gets on their first request, so a
/// retired id means an immediate 404. `test/model_facts_test.dart` keeps the
/// descriptors and this table in step.
///
/// Last verified 2026-09-29 against:
///
/// - OpenAI: developers.openai.com/api/docs/models and /deprecations. The
///   GPT-6 generation is current; `gpt-5-mini` retires 2026-12-11.
/// - Groq: console.groq.com/docs/models, /vision and /deprecations.
///   `llama-3.3-70b-versatile` and `meta-llama/llama-4-scout-17b-16e-instruct`
///   are decommissioned.
/// - Gemini: ai.google.dev/gemini-api/docs/models and /embeddings. The 2.5
///   flash models are legacy, and `gemini-embedding-2` replaces `-001`.
/// - Anthropic: the claude-api skill, models table cached 2026-09-25.
/// - NVIDIA: the docs.api.nvidia.com reference page for each id below.
/// - OpenRouter: openrouter.ai/api/v1/models. Ids track the upstream vendor.
/// - Ollama: library names the user pulls themselves. `listModels` reports
///   what is actually installed, so these are only a starting point.
library;

// Suggested models, cheapest or fastest first.

const openAiVisionModels = ['gpt-6-luna', 'gpt-6-sol'];
const openAiChatModels = openAiVisionModels;
const openAiEmbeddingModels = ['text-embedding-3-small'];

const groqVisionModels = ['qwen/qwen3.8-27b'];
const groqChatModels = ['openai/gpt-oss-120b', 'qwen/qwen3.6-27b'];

const nvidiaVisionModels = ['meta/llama-3.2-11b-vision-instruct'];
const nvidiaChatModels = ['meta/llama-3.3-70b-instruct'];
const nvidiaEmbeddingModels = ['nvidia/nv-embedqa-e5-v5'];
const nvidiaRerankModels = ['nvidia/nv-rerankqa-mistral-4b-v3'];

const openRouterModels = ['google/gemini-3.8-flash', 'openai/gpt-6-sol'];

const ollamaVisionModels = ['qwen2.5vl', 'llava'];
const ollamaChatModels = ['llama3.2'];
const ollamaEmbeddingModels = ['nomic-embed-text'];

const geminiVisionModels = ['gemini-3.5-flash', 'gemini-3.5-flash-lite'];
const geminiEmbeddingModels = ['gemini-embedding-2'];

const anthropicModels = ['claude-sonnet-5-5', 'claude-haiku-4-5'];

/// On-device model ids. The catalog in `local/model_catalog.dart` pins the
/// files themselves.
const localVisionModels = ['ocr-rules'];
const localEmbeddingModels = ['bge-small-en-v1.5'];
const localRerankModels = ['score-fusion'];

/// Every id this package suggests, for the test that catches an id added to
/// a descriptor without a doc check.
final verifiedModelIds = <String>{
  ...openAiVisionModels,
  ...openAiChatModels,
  ...openAiEmbeddingModels,
  ...groqVisionModels,
  ...groqChatModels,
  ...nvidiaVisionModels,
  ...nvidiaChatModels,
  ...nvidiaEmbeddingModels,
  ...nvidiaRerankModels,
  ...openRouterModels,
  ...ollamaVisionModels,
  ...ollamaChatModels,
  ...ollamaEmbeddingModels,
  ...geminiVisionModels,
  ...geminiEmbeddingModels,
  ...anthropicModels,
  ...localVisionModels,
  ...localEmbeddingModels,
  ...localRerankModels,
};

// Behavior that depends on the model rather than the provider. Both tables
// are allow-lists, so a model released after this date takes the path that
// works everywhere instead of one that returns 400.

/// Anthropic models that accept `output_config.format`, which is how the
/// vision adapter asks for JSON. Anything else gets a tool the model may
/// call, since forced `tool_choice` is rejected by the current lineup.
const anthropicStructuredOutputModels = [
  'claude-opus-5-5',
  'claude-opus-5',
  'claude-opus-4-8',
  'claude-opus-4-5',
  'claude-opus-4-1',
  'claude-sonnet-5-5',
  'claude-sonnet-5',
  'claude-haiku-4-5',
  'claude-fable-5',
  'claude-mythos-5',
];

bool anthropicSupportsStructuredOutput(String modelId) =>
    anthropicStructuredOutputModels.any(modelId.startsWith);

/// OpenAI models that still accept a temperature other than the default.
/// The GPT-5 and GPT-6 generations and the o-series reject one with a 400,
/// and so does any model not listed here, which keeps a new release safe.
const openAiTemperatureModels = ['gpt-4.1', 'gpt-4o', 'chatgpt-4o'];

bool openAiAcceptsTemperature(String modelId) {
  final name = modelId.split('/').last.toLowerCase();
  return openAiTemperatureModels.any(name.startsWith);
}

/// Vector length per embedding model, so stored vectors are tagged before
/// the first response arrives. Anything missing is probed once instead.
const openAiCompatibleEmbeddingDimensions = {
  'text-embedding-3-small': 1536,
  'text-embedding-3-large': 3072,
  'text-embedding-ada-002': 1536,
  'nvidia/nv-embedqa-e5-v5': 1024,
  'nomic-embed-text': 768,
  'mxbai-embed-large': 1024,
  'bge-m3': 1024,
};

/// Output size Memora asks Gemini for. Both models default to 3072, which is
/// more than memory search needs. `gemini-embedding-2` normalizes a
/// truncated vector itself; `-001` does not, so the adapter always does.
const geminiRequestedDimensions = {
  'gemini-embedding-2': 768,
  'gemini-embedding-001': 768,
};
