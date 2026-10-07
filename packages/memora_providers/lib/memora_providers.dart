/// AI provider adapters for Memora.
///
/// Each adapter implements the capability interfaces from `memora_core`.
/// Call [registerBuiltInProviders] at startup. See docs/providers.md for how
/// the pieces fit and how to add a provider.
library;

import 'src/registration.dart';

export 'src/anthropic/chat.dart' show AnthropicChatService;
export 'src/anthropic/client.dart';
export 'src/anthropic/descriptor.dart';
export 'src/anthropic/vision.dart'
    show
        AnthropicVisionService,
        anthropicImageMimeTypes,
        anthropicMaxImageBytes;
export 'src/gemini/chat.dart' show GeminiChatService;
export 'src/gemini/client.dart';
export 'src/gemini/descriptor.dart';
export 'src/gemini/embeddings.dart' show GeminiEmbeddingService;
export 'src/gemini/vision.dart' show GeminiVisionService, geminiImageMimeTypes;
export 'src/http/errors.dart';
export 'src/http/json_client.dart';
export 'src/local/client.dart';
export 'src/local/descriptor.dart';
export 'src/local/llm_chat.dart' show LocalLlmChatService;
export 'src/local/llm_models.dart';
export 'src/local/llm_prompt.dart';
export 'src/local/llm_reply_filter.dart' show LocalReplyFilter;
export 'src/local/llm_session.dart' show LocalLlmSession;
export 'src/local/llm_vision.dart' show LocalLlmVisionService;
export 'src/local/local_runtime.dart';
export 'src/local/model_catalog.dart';
export 'src/local/ocr_vision.dart';
export 'src/local/onnx_embeddings.dart';
export 'src/nvidia/rerank.dart';
export 'src/openai_compatible/chat.dart' show OpenAiChatService;
export 'src/openai_compatible/client.dart';
export 'src/openai_compatible/embeddings.dart' show OpenAiEmbeddingService;
export 'src/openai_compatible/presets.dart';
export 'src/openai_compatible/vision.dart' show OpenAiVisionService;
export 'src/registration.dart';
export 'src/shared/image_payload.dart' show ImagePayload, defaultMaxImageBytes;
export 'src/shared/model_facts.dart';
