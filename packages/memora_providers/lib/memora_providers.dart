/// AI provider adapters for Memora.
///
/// Each adapter implements the capability interfaces from `memora_core`.
/// See docs/providers.md for how to add one.
library;

export 'src/http/errors.dart';
export 'src/http/json_client.dart';
export 'src/nvidia/rerank.dart';
export 'src/openai_compatible/chat.dart' show OpenAiChatService;
export 'src/openai_compatible/client.dart';
export 'src/openai_compatible/embeddings.dart' show OpenAiEmbeddingService;
export 'src/openai_compatible/presets.dart';
export 'src/openai_compatible/vision.dart' show OpenAiVisionService;
export 'src/shared/image_payload.dart' show ImagePayload, defaultMaxImageBytes;
