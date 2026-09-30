import 'package:memora_core/memora_core.dart';
import 'package:memora_providers/memora_providers.dart';
import 'package:test/test.dart';

/// Keeps the descriptors and the dated table in `shared/model_facts.dart` in
/// step. Suggested models go stale when a vendor retires one, and a stale
/// default means a 404 on a user's first request.
void main() {
  test('every suggested model comes from the verified table', () {
    for (final descriptor in builtInProviderDescriptors) {
      for (final entry in descriptor.suggestedModels.entries) {
        expect(
          entry.value,
          isNotEmpty,
          reason: '${descriptor.id} lists ${entry.key.key} with no model',
        );
        for (final model in entry.value) {
          expect(
            verifiedModelIds,
            contains(model),
            reason:
                '${descriptor.id} suggests "$model" for ${entry.key.key}, '
                'which is not in shared/model_facts.dart',
          );
        }
      }
    }
  });

  test('cloud providers have a default for every capability they offer', () {
    for (final descriptor in builtInProviderDescriptors) {
      if (descriptor.location != ProviderLocation.cloud) continue;
      for (final capability in descriptor.capabilities) {
        final model = descriptor.defaultModel(capability);
        expect(
          model,
          isNotNull,
          reason: '${descriptor.id} has no default ${capability.key} model',
        );
        expect(model, isNotEmpty, reason: descriptor.id);
      }
    }
  });

  test('the on-device provider only suggests models it can build', () {
    final local = builtInProviderDescriptors.firstWhere((d) => d.id == 'local');
    expect(local.defaultModel(Capability.vision), ocrRulesModelId);
    expect(local.defaultModel(Capability.reranking), scoreFusionModelId);
    expect(
      localModelSpec(local.defaultModel(Capability.embeddings)!),
      isNotNull,
    );
  });

  group('model behavior tables', () {
    test('current Anthropic models take structured outputs', () {
      for (final model in [
        'claude-opus-5-5',
        'claude-sonnet-5-5',
        'claude-opus-5',
        'claude-sonnet-5',
        'claude-haiku-4-5',
        'claude-fable-5-1',
        'claude-opus-4-8',
      ]) {
        expect(anthropicSupportsStructuredOutput(model), isTrue, reason: model);
      }
    });

    test('older and unknown Anthropic models do not', () {
      for (final model in [
        'claude-sonnet-4-6',
        'claude-opus-4-6',
        'claude-3-5-sonnet-20241022',
        'claude-opus-7',
      ]) {
        expect(
          anthropicSupportsStructuredOutput(model),
          isFalse,
          reason: model,
        );
      }
    });

    test('only known OpenAI models accept a temperature', () {
      expect(openAiAcceptsTemperature('gpt-4.1-mini'), isTrue);
      expect(openAiAcceptsTemperature('gpt-4o'), isTrue);
      expect(openAiAcceptsTemperature('openai/gpt-4.1-mini'), isTrue);
      for (final model in [
        'gpt-6-luna',
        'gpt-6-sol',
        'gpt-5-mini',
        'o3-mini',
        'openai/gpt-6-sol',
        'something-new',
      ]) {
        expect(openAiAcceptsTemperature(model), isFalse, reason: model);
      }
    });
  });
}
