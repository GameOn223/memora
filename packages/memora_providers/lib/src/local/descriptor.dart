import 'package:memora_core/memora_core.dart';

import '../shared/model_facts.dart';

/// Model id of on-device vision: ML Kit OCR plus rule-based extraction.
const ocrRulesModelId = 'ocr-rules';

/// Model id of the on-device reranker.
const scoreFusionModelId = 'score-fusion';

const localDescriptor = ProviderDescriptor(
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
    // OCR plus rules first, then the generative models that read images.
    Capability.vision: localVisionModels,
    // Only offered once the user has imported the file.
    Capability.chat: localChatModels,
    // Must match an entry in the local model catalog.
    Capability.embeddings: localEmbeddingModels,
    Capability.reranking: localRerankModels,
  },
);
