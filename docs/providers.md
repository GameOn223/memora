# AI providers

This guide covers how Memora talks to AI models: the capability model in `memora_core`, the adapters shipped in `packages/memora_providers`, and the steps for adding a provider of your own. Read section 7 of [architecture.md](architecture.md) first if you haven't.

## Contents

1. [Capabilities, descriptors and the router](#1-capabilities-descriptors-and-the-router)
2. [Built-in providers](#2-built-in-providers)
3. [How the adapters behave](#3-how-the-adapters-behave)
4. [Local-only mode](#4-local-only-mode)
5. [Adding a provider](#5-adding-a-provider)

## 1. Capabilities, descriptors and the router

Memora needs four things from AI, and each one is a separate interface in `memora_core`:

| Capability | Interface | Used for |
|------------|-----------|----------|
| `vision` | `VisionService` | turning an image into a `MemoryUnderstanding`, and checking one fact against the image |
| `chat` | `ChatService` | the Ask agent, with tool calls |
| `embeddings` | `EmbeddingService` | vectors for semantic search |
| `reranking` | `RerankService` | reordering the top search results |

The user picks a provider and a model for each capability on its own, so vision can run on Gemini while chat goes to a laptop running Ollama.

The pieces that make that work:

- **`ProviderDescriptor`** is static data about a provider: a stable `id`, a display name, where it runs (`onDevice`, `selfHosted` or `cloud`), the capabilities it offers with suggested models for each, whether it needs an API key, and whether the base URL can be edited.
- **`ProviderClient`** is a configured provider. It hands out a service per capability for a given model id, or `null` when it can't, and it can list models and test the connection.
- **`ProviderRegistry`** maps provider ids to descriptors and factories. A factory takes a `ProviderConfig` (base URL and key) and returns a `ProviderClient`.
- **`CapabilityRouter`** reads the user's selections, applies local-only mode, loads the API key from the secret store, builds the client and returns the service. When it can't, it throws `CapabilityUnavailableException` with a reason such as `missingApiKey` or `blockedByLocalOnly`.

The app wires it together once at startup:

```dart
final registry = ProviderRegistry();
registerBuiltInProviders(
  registry,
  httpClient: http.Client(),
  local: LocalRuntime(
    ocr: mlKitOcr,
    embeddingRuntime: onnxRuntime,
    modelFiles: modelDownloads,
  ),
);
final router = CapabilityRouter(
  registry: registry,
  settings: AiSettingsRepository(settingsStore),
  secrets: secretStore,
);
```

### Errors

Adapters never let raw HTTP or socket errors escape. Everything becomes one of three `AiException` subtypes, and the processing queue decides what to do from the type (architecture.md, section 5.3):

| Exception | Raised for |
|-----------|-----------|
| `AiTransientException` | timeouts, lost connections, 408, 409, 425, 429, 5xx, bodies that aren't JSON. Carries `retryAfter` when the provider sent `Retry-After`. |
| `AiConfigurationException` | 401 and 403 ("The API key was rejected"), 404 ("Model or endpoint not found"), 402, other 400s, a missing base URL |
| `AiContentException` | 400s naming the image, safety, moderation, a policy or a content filter, 413, refusals, safety stops, images that are too big or of an unsupported type, replies that never contain the expected JSON |

The split matters because a content error fails that memory for good, while a configuration error pauses the queue with something the user can fix. So the content patterns are kept narrow and an ambiguous 400 stays configuration. A request-shape bug on Memora's side, such as `Invalid value for 'messages[0].content'`, pauses the queue once instead of quietly failing every image.

`JsonClient` does this mapping in one place. Error messages include the provider's own message cut to 200 characters. Credential header values and anything shaped like a known key (`sk-...`, `sk-ant-...`, `nvapi-...`, `gsk_...`, `AIza...`) are replaced with `[redacted]` first. A 401 never includes the provider's text at all, because some providers echo part of the key back.

## 2. Built-in providers

`registerBuiltInProviders` registers these, on-device first. `builtInProviderDescriptors` lists them in the same order.

| Id | Name | Location | API key | Default base URL | Capabilities |
|----|------|----------|---------|------------------|--------------|
| `local` | On this device | on device | none | none | vision, embeddings, reranking |
| `openai` | OpenAI | cloud | required, `sk-...` | `https://api.openai.com/v1` | vision, chat, embeddings |
| `groq` | Groq | cloud | required, `gsk_...` | `https://api.groq.com/openai/v1` | vision, chat |
| `nvidia` | NVIDIA | cloud | required, `nvapi-...` | `https://integrate.api.nvidia.com/v1` | vision, chat, embeddings, reranking |
| `openrouter` | OpenRouter | cloud | required, `sk-or-...` | `https://openrouter.ai/api/v1` | vision, chat |
| `ollama` | Ollama | self-hosted | optional | `http://localhost:11434/v1` (editable) | vision, chat, embeddings |
| `lmstudio` | LM Studio | self-hosted | optional | `http://localhost:1234/v1` (editable) | vision, chat, embeddings |
| `custom` | Custom OpenAI-compatible server | self-hosted | optional | none, the user enters one | vision, chat, embeddings |
| `gemini` | Google Gemini | cloud | required, `AIza...` | `https://generativelanguage.googleapis.com/v1beta` | vision, chat, embeddings |
| `anthropic` | Anthropic | cloud | required, `sk-ant-...` | `https://api.anthropic.com/v1` | vision, chat |

### Suggested models and other facts with an expiry date

Which model each provider starts on lives in `lib/src/shared/model_facts.dart`, with the date it was last checked and the vendor pages used. Everything version-dependent sits in that one file: the suggested ids, which Anthropic models take structured outputs, which OpenAI models still accept a temperature, and the vector length of well known embedding models.

Keep it there rather than spreading it through the adapters. A suggestion is what a user gets on their first request, so a retired id is an immediate 404, and these expire quietly: several ids this package shipped with were retired within two months. `test/model_facts_test.dart` fails when a descriptor names a model the file doesn't list, and every behavior table is an allow-list, so a model released after the last check takes the path that works everywhere instead of one that returns 400.

Suggestions are a starting point either way. `listModels` asks the provider for its current list where there's an endpoint for it (`GET /models` everywhere except the local provider), and the user can type any id.

"Optional" keys use `ProviderDescriptor.apiKeyOptional`. The router passes a saved key to those providers but doesn't mark them unavailable without one, which suits a home server behind an authenticating proxy.

### On-device models

The local provider's embedding model isn't bundled. `model_catalog.dart` pins it:

| Spec | File | Size | Check |
|------|------|------|-------|
| `bgeSmallEnV15` (384 dimensions, revision `ea104dacec62c0de699686887e3f920caeb4f3e3`) | `onnx/model_quantized.onnx` | 34,014,426 bytes | SHA-256 `6c9c6101a956d62dfb5e7190c538226c0c5bb9cb27b651234b6df063ee7dbfe4` |
| | `vocab.txt` | 231,508 bytes | Git blob SHA-1 `fb140275c155a9c7c5a3b3e0e77a9e839594a938` |

The app downloads the files through `LocalModelFiles` and must verify them before reporting `LocalModelState.ready`. Until then `OnnxEmbeddingService.embed` throws `CapabilityUnavailableException` with `modelNotDownloaded`.

## 3. How the adapters behave

### OpenAI-compatible (`openai_compatible/`)

One adapter serves seven presets. `OpenAiCompatibleProfile.forProvider` holds the differences:

- **JSON for vision.** OpenAI, OpenRouter and LM Studio get `response_format: {type: json_schema}` with the shared schema and `additionalProperties: false` added to every object. OpenAI also sets `strict: true`, which makes the reply match the schema, so there is nothing to retry. Everyone else gets `{type: json_object}`. If a server rejects `response_format`, or the reply has no JSON object in it, the adapter asks once more without it. JSON inside a fenced code block or surrounded by prose still parses.
- **Token limits.** OpenAI gets `max_completion_tokens`, the rest `max_tokens`.
- **Temperature.** On the OpenAI and OpenRouter presets, only models listed in `openAiTemperatureModels` get a `temperature`. The GPT-5 and GPT-6 generations and the o-series reject a non-default one with a 400, and so does anything the list doesn't know, which keeps a new release safe. Those same models get 8,192 extra output tokens, since reasoning counts against the limit. Self-hosted presets always send the temperature.
- **Embeddings.** NVIDIA needs `input_type` (`passage` or `query`), `encoding_format: float` and `truncate: END`. Vectors are sorted by `index` and L2-normalized. Well known models have their length in `openAiCompatibleEmbeddingDimensions`; for anything else, `resolveModel()` embeds a single token once to learn it, and the answer is shared by every later service for that provider and model. Call `resolveModel()` before tagging stored vectors and `EmbeddingModelInfo.dimensions` is never a guess. An Ollama `:latest` tag is trimmed from the stored id, so `nomic-embed-text` and `nomic-embed-text:latest` stay one embedding space.
- **Reranking.** `NvidiaRerankService` posts to `https://ai.api.nvidia.com/v1/retrieval/<model>/reranking` with dots in the model name written as underscores, and maps `rankings[].logit` back to candidate ids. Candidates missing from the response are placed last.
- **Errors in a 200.** OpenRouter reports upstream failures as an `error` object inside a successful response. The shared endpoint maps those too.

### Gemini (`gemini/`)

- The key goes in the `x-goog-api-key` header, never in the URL.
- Vision uses `responseMimeType: application/json` with `responseSchema`. The schema is converted to Gemini's subset: `["string", "null"]` becomes `nullable: true`, and keys it doesn't accept, such as `additionalProperties`, are dropped. A `SAFETY` style finish reason or a blocked prompt is a content error.
- Chat maps assistant turns to `role: model` and tool results to `functionResponse` parts, grouped into one user turn. A tool with no parameters is declared without a `parameters` object, because Gemini rejects an empty one.
- Gemini's embedding models are asked for 768 of their 3072 dimensions and normalized locally, which `gemini-embedding-001` needs for a truncated size and the newer models do anyway. Up to 100 texts go in one `batchEmbedContents` call, and an unlisted model learns its length through `resolveModel()`.
- An image is checked against Gemini's 20 MB request cap **after** base64, which inflates a file by a third. A 16 MB photo is refused locally rather than by the API.

### Anthropic (`anthropic/`)

- Requests carry `x-api-key` and `anthropic-version: 2023-06-01`.
- Vision asks for JSON with `output_config: {format: {type: json_schema, schema}}` on every model in `anthropicStructuredOutputModels`, and reads the JSON out of the reply text. Any other model, including one released after that list was written, gets a `record_memory` or `record_verification` tool with `tool_choice: auto` and an instruction to use it, then falls back to JSON in the text. A forced `tool_choice` is never sent: the current lineup returns a 400 for it, which would fail every image with a configuration error and pause the queue.
- No `temperature` is sent, because current models refuse sampling settings other than the defaults. The chat output limit gets the same 8,192 token headroom since newer models think by default.
- Images must be JPEG, PNG, GIF or WebP and at most 5 MB. Anything else fails before a request is made.

### Replaying reasoning in tool loops

Reasoning models attach data to the turns where they call tools. Anthropic sends signed thinking blocks and Gemini 3 sends thought signatures with its call ids. OpenRouter passes along `reasoning_details` from whichever model it routed to. The provider expects that data back, unchanged, in the next request of the same tool loop.

Memora's `AssistantEntry` only carries text and tool calls, so each chat adapter keeps the raw assistant turn in a `TurnReplayCache`, keyed by the provider, the model and the tool call ids. When the chat engine sends an `AssistantEntry` with the same ids, the adapter sends the original turn instead of rebuilding it. The key includes the provider because one cache serves every OpenAI-compatible preset, and two servers must never read each other's entries.

The cache lives in memory, holds the 64 most recent turns and is never written anywhere. So it misses when the app restarts partway through a conversation, or when a very long chat pushes a turn out. On a miss the adapter rebuilds the assistant turn from the transcript, which drops the thinking blocks or signatures the original carried. Providers differ in how they take that: most ignore it, and a model that enforces preserved thinking can reject the edited history. The turn then fails as a transient or configuration error, and the next question starts a fresh loop that works. Nothing is lost from the conversation itself, since every saved message is text.

### Transcript windows

Ask sends a window of recent messages, so a request can start partway through an earlier tool loop. The helpers in `shared/transcript.dart` trim that before it reaches a provider. Anthropic and Gemini reject a transcript whose first message isn't from the user, so those adapters start at the first user turn. The OpenAI-compatible adapter drops leading tool results, which would otherwise answer a tool call the window no longer holds. Both helpers leave the list alone when trimming would empty it.

### On this device (`local/`)

- `OcrVisionService` runs `OcrEngine` on `VisionRequest.absoluteImagePath` and passes the result to the `OcrUnderstandingExtractor` in `LocalRuntime`, which defaults to `RuleBasedExtractor` from core. Without a path it throws a content error.
- On-device `verify` matches digits and can only ever confirm. `₹2,103` matches `2,103.00` and `₹1,24,900` matches `124900`, and the observed value is always null, so an unconfirmed answer means "could not tell" rather than "wrong". A money field (`amount`, `total`, `price` and similar) is only confirmed from a line that reads like money, so an order number sharing those digits doesn't pass as the total. A value made of several numbers, such as the date `2026-08-31`, is never confirmed, because its parts would match unrelated numbers on the page. The answer verifier treats an unconfirmed result as no label, so both limits are quiet.
- `OnnxEmbeddingService` tokenizes with `WordPieceTokenizer` in Dart (vocab read once per file), prefixes queries with `Represent this sentence for searching relevant passages: `, and sends batches of 16 to `EmbeddingRuntime`. Its `model` is `local/bge-small-en-v1.5`, version `ea104dacec62` (the first 12 characters of the revision), 384 dimensions.
- Reranking returns core's `FusionReranker`.
- `testConnection` always succeeds and says whether the embedding model is ready.

## 4. Local-only mode

When local-only mode is on, `CapabilityRouter` runs `LocalOnlyPolicy` before it builds any client. The decision depends only on the descriptor's `location` and, for self-hosted providers, the base URL the user saved.

| Location | Providers | Allowed in local-only mode |
|----------|-----------|----------------------------|
| `onDevice` | `local` | always |
| `selfHosted` | `ollama`, `lmstudio`, `custom` | only when the base URL host is on this device or a private network |
| `cloud` | `openai`, `groq`, `nvidia`, `openrouter`, `gemini`, `anthropic` | never |

A self-hosted host passes when it is:

- `localhost` or a loopback address (`127.0.0.0/8`, `::1`)
- a private IPv4 address (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`)
- link-local (`169.254.0.0/16`, `fe80::/10`)
- an IPv6 unique local address (`fc00::/7`)
- a name ending in `.local`

So `http://192.168.1.20:11434/v1` is allowed and `https://ollama.example.com/v1` is refused, even though both are Ollama. The router refuses before creating a client, so a blocked provider never sees a request. Memora doesn't fall back to another provider either. The capability shows as unavailable with `blockedByLocalOnly` until the user changes something.

The `custom` preset is `selfHosted` on purpose. Pointing it at a public URL works normally, but local-only mode will block it, which is what a user who switched that mode on would expect.

## 5. Adding a provider

Most new services speak the OpenAI protocol. For those, add a preset rather than an adapter:

1. Add a `const ProviderDescriptor` in `lib/src/openai_compatible/presets.dart` and append it to `openAiCompatibleDescriptors`.
2. If it needs different request details, add a case to `OpenAiCompatibleProfile.forProvider`.
3. Add fixtures and tests as in step 5 below. Registration happens automatically.

For a provider with its own protocol, create a folder under `lib/src/<provider>/` and follow these steps. The Anthropic adapter is the smallest complete example.

### Step 1: descriptor

`descriptor.dart` holds one `const ProviderDescriptor`. Pick an id that will never change, since settings and processing records store it. Set `location` honestly: it decides what local-only mode allows. Put the suggested model ids in `shared/model_facts.dart` and point the descriptor at them, cheaper and faster ones first, and note in that file's header where you checked them. The descriptor keeps only the ids that came from the vendor's own documentation that day.

### Step 2: client

`client.dart` implements `ProviderClient`. Build a `ProviderEndpoint` from `lib/src/shared/endpoint.dart` with the provider id, `config.baseUrl ?? descriptor.defaultBaseUrl`, the key, a `JsonClient` and a function that turns the key into headers. Then:

- return a service from each capability method the provider supports, and `null` from the rest
- make `listModels` fall back to the descriptor's suggestions when listing fails
- make `testConnection` return `ConnectionCheck.failed` with the exception message rather than throwing

Put credentials in headers. `JsonClient` redacts the values of `authorization`, `x-api-key`, `x-goog-api-key` and `api-key` from error messages, and a key in a URL could end up in an exception text.

### Step 3: services

One file per capability. A few rules keep adapters interchangeable:

- **Vision** sends `VisionPrompts.analyzeInstructions(request)` and `VisionPrompts.analyzeUserText` with the image, asks for `VisionPrompts.understandingSchema` using the provider's structured output feature, and returns `MemoryUnderstanding.fromJson`. `verify` does the same with `verifyInstructions`, `verificationSchema` and `parseVerification` from `shared/verification.dart`. Check the image with `ImagePayload.of`, passing the provider's size limit and accepted types. Use `extractJsonObject` as a fallback when a model wraps its JSON in text.
- **Chat** maps `ChatRequest.entries` in order, sends `tools` when there are any, and returns every tool call with a stable id. Parse tool arguments with `decodeArguments`, which turns bad JSON into an empty map so the tool reports a validation error the model can fix. If the provider attaches reasoning data to tool calls, keep the raw turn in a `TurnReplayCache`.
- **Embeddings** return one L2-normalized vector per input in input order (`normalizedVector` helps). `model` must report the real dimensions, and `version` should change whenever the same model id would produce different vectors.
- **Reranking** returns a score for every candidate, best first.
- Throw only `AiException` subtypes. Pick `AiContentException` when retrying the same image can't help, `AiConfigurationException` when the user has to change settings, and `AiTransientException` for everything worth retrying later.

### Step 4: register

Add the descriptor to `builtInProviderDescriptors` and a `registry.register` call to `registerBuiltInProviders` in `lib/src/registration.dart`, then export the public types from `lib/memora_providers.dart`. The registration test checks that every descriptor's capabilities match the services its client actually returns.

### Step 5: tests with fixtures

Tests never touch the network. `test/support/scripted_http.dart` wraps `MockClient` from `package:http/testing.dart`: queue responses with `reply` or `replyFixture`, run the adapter, then inspect `requests` and `body(i)`.

1. Record the provider's real request and response shapes as JSON files under `test/fixtures/<provider>/`. Take them from the provider's API reference. Never paste a real key or real personal data into a fixture.
2. Write golden request fixtures and compare with `fixtureJsonWith`, which swaps placeholders like `"<analyze_instructions>"` for real values so long prompts aren't copied into the file.
3. Cover at least: the vision request and parsed understanding, a refusal or safety stop, `verify`, a chat request with tools and tool results, a tool call round trip, embedding order and normalization, `listModels` with its fallback, `testConnection`, and the status codes the provider documents.
4. Run the checks from `packages/memora_providers`:

```sh
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

If the provider needs something the core contracts can't express, open an issue before changing `memora_core`. Contract changes there have to be additive and they affect every other adapter.
