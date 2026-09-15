import 'package:memora_core/memora_core.dart';

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
    Capability.embeddings,
    Capability.reranking,
  },
  suggestedModels: {
    Capability.vision: [ocrRulesModelId],
    // Must match an entry in the local model catalog.
    Capability.embeddings: ['bge-small-en-v1.5'],
    Capability.reranking: [scoreFusionModelId],
  },
);
