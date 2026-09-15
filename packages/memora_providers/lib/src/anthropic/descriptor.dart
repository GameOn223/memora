import 'package:memora_core/memora_core.dart';

const anthropicDescriptor = ProviderDescriptor(
  id: 'anthropic',
  displayName: 'Anthropic',
  location: ProviderLocation.cloud,
  capabilities: {Capability.vision, Capability.chat},
  suggestedModels: {
    Capability.vision: ['claude-sonnet-5', 'claude-haiku-4-5'],
    Capability.chat: ['claude-sonnet-5', 'claude-haiku-4-5'],
  },
  requiresApiKey: true,
  apiKeyHint: 'sk-ant-...',
  defaultBaseUrl: 'https://api.anthropic.com/v1',
  homepage: 'https://platform.claude.com',
);
