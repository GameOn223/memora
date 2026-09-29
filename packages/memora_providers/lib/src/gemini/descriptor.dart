import 'package:memora_core/memora_core.dart';

const geminiDescriptor = ProviderDescriptor(
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
  apiKeyHint: 'AIza...',
  defaultBaseUrl: 'https://generativelanguage.googleapis.com/v1beta',
  homepage: 'https://aistudio.google.com',
);
