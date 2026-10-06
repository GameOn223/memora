import 'package:meta/meta.dart';

import '../model/processing.dart';
import 'capabilities.dart';

/// Where a provider runs, which decides what local-only mode allows.
enum ProviderLocation {
  /// Runs inside Memora on this phone.
  onDevice,

  /// A server the user runs, reached at a base URL they entered.
  selfHosted,

  /// A third-party cloud service.
  cloud,
}

/// Static description of a provider, used by settings and the router.
@immutable
class ProviderDescriptor {
  const ProviderDescriptor({
    required this.id,
    required this.displayName,
    required this.location,
    required this.capabilities,
    this.suggestedModels = const {},
    this.requiresApiKey = false,
    this.apiKeyOptional = false,
    this.defaultBaseUrl,
    this.baseUrlEditable = false,
    this.apiKeyHint,
    this.homepage,
  });

  /// Stable id used in settings and processing records, for example `groq`.
  final String id;
  final String displayName;
  final ProviderLocation location;
  final Set<Capability> capabilities;

  /// Starting points for the model picker. Users can type any model id.
  final Map<Capability, List<String>> suggestedModels;
  final bool requiresApiKey;

  /// The provider works without a key but uses one when the user saves it,
  /// for example a self-hosted server behind an authenticating proxy.
  final bool apiKeyOptional;
  final String? defaultBaseUrl;
  final bool baseUrlEditable;

  /// Placeholder for the key field, for example `gsk_...`.
  final String? apiKeyHint;
  final String? homepage;

  bool supports(Capability capability) => capabilities.contains(capability);

  String? defaultModel(Capability capability) {
    final models = suggestedModels[capability];
    return models == null || models.isEmpty ? null : models.first;
  }
}

/// Everything needed to build a client for one provider.
@immutable
class ProviderConfig {
  const ProviderConfig({required this.providerId, this.baseUrl, this.apiKey});

  final String providerId;
  final String? baseUrl;
  final String? apiKey;
}

/// Result of "Test connection" in settings.
@immutable
class ConnectionCheck {
  const ConnectionCheck.ok({this.detail}) : ok = true;

  const ConnectionCheck.failed(String this.detail) : ok = false;

  final bool ok;
  final String? detail;
}

/// A configured provider that can hand out capability services.
///
/// Methods return null when the provider doesn't offer that capability.
abstract interface class ProviderClient {
  ProviderDescriptor get descriptor;

  VisionService? vision(String modelId);

  ChatService? chat(String modelId);

  EmbeddingService? embeddings(String modelId);

  RerankService? reranker(String modelId);

  /// Model ids the provider reports for [capability]. Falls back to the
  /// suggested list when the provider has no listing endpoint.
  Future<List<String>> listModels(Capability capability);

  /// Whether [modelId] can serve [capability] right now.
  ///
  /// A provider whose model is a file on this phone answers false until the
  /// file is there, and the router reports that as
  /// [UnavailableReason.modelNotDownloaded] rather than handing out a
  /// service that would fail on first use. Anything reached over the network
  /// mixes in [ModelsAlwaysReady].
  Future<bool> isModelReady(Capability capability, String modelId);

  Future<ConnectionCheck> testConnection();
}

/// [ProviderClient.isModelReady] for providers that need nothing on this
/// phone before a request.
mixin ModelsAlwaysReady {
  Future<bool> isModelReady(Capability capability, String modelId) async =>
      true;
}

typedef ProviderFactory = ProviderClient Function(ProviderConfig config);
