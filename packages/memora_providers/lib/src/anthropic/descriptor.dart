import 'package:memora_core/memora_core.dart';

import '../shared/model_facts.dart';

const anthropicDescriptor = ProviderDescriptor(
  id: 'anthropic',
  displayName: 'Anthropic',
  location: ProviderLocation.cloud,
  capabilities: {Capability.vision, Capability.chat},
  suggestedModels: {
    Capability.vision: anthropicModels,
    Capability.chat: anthropicModels,
  },
  requiresApiKey: true,
  apiKeyHint: 'sk-ant-...',
  defaultBaseUrl: 'https://api.anthropic.com/v1',
  homepage: 'https://platform.claude.com',
);
