import 'package:memora_core/memora_core.dart';

import '../shared/model_facts.dart';

const geminiDescriptor = ProviderDescriptor(
  id: 'gemini',
  displayName: 'Google Gemini',
  location: ProviderLocation.cloud,
  capabilities: {Capability.vision, Capability.chat, Capability.embeddings},
  suggestedModels: {
    Capability.vision: geminiVisionModels,
    Capability.chat: geminiVisionModels,
    Capability.embeddings: geminiEmbeddingModels,
  },
  requiresApiKey: true,
  apiKeyHint: 'AIza...',
  defaultBaseUrl: 'https://generativelanguage.googleapis.com/v1beta',
  homepage: 'https://aistudio.google.com',
);
