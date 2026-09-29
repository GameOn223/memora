import 'package:http/http.dart' as http;
import 'package:memora_core/memora_core.dart';

import 'anthropic/client.dart';
import 'anthropic/descriptor.dart';
import 'gemini/client.dart';
import 'gemini/descriptor.dart';
import 'local/client.dart';
import 'local/descriptor.dart';
import 'local/local_runtime.dart';
import 'openai_compatible/client.dart';
import 'openai_compatible/presets.dart';

/// Every provider Memora ships, on-device first, in registration order.
const builtInProviderDescriptors = [
  localDescriptor,
  ...openAiCompatibleDescriptors,
  geminiDescriptor,
  anthropicDescriptor,
];

/// Registers every shipped provider with [registry].
///
/// All network adapters share [httpClient], which the app owns and closes.
/// The on-device provider runs on the ports in [local].
void registerBuiltInProviders(
  ProviderRegistry registry, {
  required http.Client httpClient,
  required LocalRuntime local,
}) {
  registry.register(localDescriptor, (_) => LocalProviderClient(local));
  for (final descriptor in openAiCompatibleDescriptors) {
    registry.register(
      descriptor,
      (config) =>
          OpenAiCompatibleClient(descriptor, config, httpClient: httpClient),
    );
  }
  registry.register(
    geminiDescriptor,
    (config) => GeminiClient(config, httpClient: httpClient),
  );
  registry.register(
    anthropicDescriptor,
    (config) => AnthropicClient(config, httpClient: httpClient),
  );
}
