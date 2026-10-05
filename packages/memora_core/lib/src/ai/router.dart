import 'package:meta/meta.dart';

import '../model/processing.dart';
import '../ports/stores.dart';
import 'capabilities.dart';
import 'errors.dart';
import 'local_only_policy.dart';
import 'provider.dart';
import 'registry.dart';
import 'settings.dart';

/// A capability service together with where it came from.
@immutable
class Resolved<T> {
  const Resolved({
    required this.service,
    required this.provider,
    required this.modelId,
  });

  final T service;
  final ProviderDescriptor provider;
  final String modelId;
}

/// Whether a capability can be used, for settings and chat headers.
@immutable
class CapabilityStatus {
  const CapabilityStatus.available(this.provider, this.modelId)
    : available = true,
      reason = null;

  const CapabilityStatus.unavailable(this.reason, {this.provider, this.modelId})
    : available = false;

  final bool available;
  final UnavailableReason? reason;
  final ProviderDescriptor? provider;
  final String? modelId;
}

/// Turns the user's per-capability choices into ready services, applying
/// local-only mode and API key checks on the way.
class CapabilityRouter {
  CapabilityRouter({
    required this._registry,
    required this._settings,
    required this._secrets,
    this._policy = const LocalOnlyPolicy(),
  });

  final ProviderRegistry _registry;
  final AiSettingsRepository _settings;
  final SecretStore _secrets;
  final LocalOnlyPolicy _policy;

  /// Secret store key holding a provider's API key.
  static String apiKeyName(String providerId) => 'provider.$providerId.api_key';

  Future<Resolved<VisionService>> vision() =>
      _resolve(Capability.vision, (c, m) => c.vision(m));

  Future<Resolved<ChatService>> chat() =>
      _resolve(Capability.chat, (c, m) => c.chat(m));

  Future<Resolved<EmbeddingService>> embeddings() =>
      _resolve(Capability.embeddings, (c, m) => c.embeddings(m));

  Future<Resolved<RerankService>> reranker() =>
      _resolve(Capability.reranking, (c, m) => c.reranker(m));

  /// Builds a client for [providerId] with its saved URL and key, ignoring
  /// selections. Used by "Test connection" and the model picker.
  Future<ProviderClient> clientFor(String providerId) async {
    final settings = await _settings.load();
    final descriptor = _registry.descriptor(providerId);
    if (descriptor == null) {
      throw ArgumentError.value(providerId, 'providerId', 'Not registered');
    }
    return _registry.create(await _configFor(descriptor, settings));
  }

  Future<Map<Capability, CapabilityStatus>> statuses() async {
    final result = <Capability, CapabilityStatus>{};
    for (final capability in Capability.values) {
      try {
        final resolved = await _resolve<Object>(capability, (client, model) {
          return switch (capability) {
            Capability.vision => client.vision(model),
            Capability.chat => client.chat(model),
            Capability.embeddings => client.embeddings(model),
            Capability.reranking => client.reranker(model),
          };
        });
        result[capability] = CapabilityStatus.available(
          resolved.provider,
          resolved.modelId,
        );
      } on CapabilityUnavailableException catch (e) {
        final settings = await _settings.load();
        final selection = settings.selections[capability];
        result[capability] = CapabilityStatus.unavailable(
          e.reason,
          provider: selection == null
              ? null
              : _registry.descriptor(selection.providerId),
          modelId: selection?.modelId,
        );
      }
    }
    return result;
  }

  /// Selected providers that send data off the phone, each listed once.
  /// Drives the cloud disclosure notice and the Wi-Fi constraint.
  Future<List<ProviderDescriptor>> offDeviceProviders() async {
    final settings = await _settings.load();
    final seen = <String>{};
    final result = <ProviderDescriptor>[];
    for (final selection in settings.selections.values) {
      final descriptor = _registry.descriptor(selection.providerId);
      if (descriptor == null ||
          descriptor.location == ProviderLocation.onDevice ||
          !seen.add(descriptor.id)) {
        continue;
      }
      result.add(descriptor);
    }
    return result;
  }

  Future<Resolved<T>> _resolve<T extends Object>(
    Capability capability,
    T? Function(ProviderClient client, String modelId) pick,
  ) async {
    final settings = await _settings.load();
    final selection = settings.selections[capability];
    if (selection == null) {
      throw CapabilityUnavailableException(
        capability,
        UnavailableReason.notConfigured,
      );
    }
    final descriptor = _registry.descriptor(selection.providerId);
    if (descriptor == null) {
      throw CapabilityUnavailableException(
        capability,
        UnavailableReason.notConfigured,
      );
    }
    if (!descriptor.supports(capability)) {
      throw CapabilityUnavailableException(
        capability,
        UnavailableReason.unsupportedByProvider,
        providerName: descriptor.displayName,
        modelId: selection.modelId,
      );
    }
    final config = await _configFor(descriptor, settings);
    if (settings.localOnly && !_policy.allows(descriptor, config.baseUrl)) {
      throw CapabilityUnavailableException(
        capability,
        UnavailableReason.blockedByLocalOnly,
        providerName: descriptor.displayName,
        modelId: selection.modelId,
      );
    }
    if (descriptor.requiresApiKey && (config.apiKey ?? '').isEmpty) {
      throw CapabilityUnavailableException(
        capability,
        UnavailableReason.missingApiKey,
        providerName: descriptor.displayName,
        modelId: selection.modelId,
      );
    }
    final service = pick(_registry.create(config), selection.modelId);
    if (service == null) {
      throw CapabilityUnavailableException(
        capability,
        UnavailableReason.unsupportedByProvider,
        providerName: descriptor.displayName,
        modelId: selection.modelId,
      );
    }
    return Resolved(
      service: service,
      provider: descriptor,
      modelId: selection.modelId,
    );
  }

  Future<ProviderConfig> _configFor(
    ProviderDescriptor descriptor,
    AiSettings settings,
  ) async {
    return ProviderConfig(
      providerId: descriptor.id,
      baseUrl: settings.baseUrls[descriptor.id] ?? descriptor.defaultBaseUrl,
      apiKey: descriptor.requiresApiKey || descriptor.apiKeyOptional
          ? await _secrets.read(apiKeyName(descriptor.id))
          : null,
    );
  }
}
