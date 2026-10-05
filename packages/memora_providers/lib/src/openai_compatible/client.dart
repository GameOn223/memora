import 'package:http/http.dart' as http;
import 'package:memora_core/memora_core.dart';

import '../http/json_client.dart';
import '../nvidia/rerank.dart';
import '../shared/endpoint.dart';
import '../shared/json_read.dart';
import 'chat.dart';
import 'embeddings.dart';
import 'presets.dart';
import 'vision.dart';

/// [ProviderClient] for every server that speaks the OpenAI chat
/// completions protocol. The [descriptor] decides which services exist and
/// its id picks the [OpenAiCompatibleProfile].
class OpenAiCompatibleClient implements ProviderClient {
  OpenAiCompatibleClient(
    this.descriptor,
    ProviderConfig config, {
    required http.Client httpClient,
    OpenAiCompatibleProfile? profile,
    Duration timeout = const Duration(seconds: 90),
  }) : _httpClient = httpClient,
       _apiKey = config.apiKey,
       _timeout = timeout,
       _profile = profile ?? OpenAiCompatibleProfile.forProvider(descriptor.id),
       _endpoint = ProviderEndpoint(
         providerId: descriptor.id,
         baseUrl: config.baseUrl ?? descriptor.defaultBaseUrl,
         apiKey: config.apiKey,
         http: JsonClient(httpClient, timeout: timeout),
         authHeaders: (key) => {'authorization': 'Bearer $key'},
       );

  @override
  final ProviderDescriptor descriptor;
  final http.Client _httpClient;
  final String? _apiKey;
  final Duration _timeout;
  final OpenAiCompatibleProfile _profile;
  final ProviderEndpoint _endpoint;

  @override
  VisionService? vision(String modelId) =>
      descriptor.supports(Capability.vision)
      ? OpenAiVisionService(_endpoint, _profile, modelId)
      : null;

  @override
  ChatService? chat(String modelId) => descriptor.supports(Capability.chat)
      ? OpenAiChatService(_endpoint, _profile, modelId)
      : null;

  @override
  EmbeddingService? embeddings(String modelId) =>
      descriptor.supports(Capability.embeddings)
      ? OpenAiEmbeddingService(_endpoint, _profile, modelId)
      : null;

  @override
  RerankService? reranker(String modelId) =>
      descriptor.id == 'nvidia' && descriptor.supports(Capability.reranking)
      ? NvidiaRerankService(
          httpClient: _httpClient,
          apiKey: _apiKey,
          modelId: modelId,
          timeout: _timeout,
        )
      : null;

  List<String> _suggested(Capability capability) =>
      descriptor.suggestedModels[capability] ?? const [];

  @override
  Future<List<String>> listModels(Capability capability) async {
    if (!descriptor.supports(capability)) return const [];
    // Reranking models aren't listed by /models.
    if (capability == Capability.reranking) return _suggested(capability);
    try {
      final json = await _endpoint.get('/models');
      final ids = _filter(capability, asList(json['data']));
      return ids.isEmpty ? _suggested(capability) : ids;
    } on AiException {
      return _suggested(capability);
    }
  }

  /// Splits one mixed model list by capability using the hints servers give:
  /// OpenRouter lists input modalities, and embedding models have "embed" in
  /// their names nearly everywhere.
  static List<String> _filter(Capability capability, List<Object?> data) {
    final all = <String>[];
    final withImages = <String>[];
    var hasModalities = false;
    for (final raw in data) {
      final item = asObject(raw);
      final id = asString(item?['id']);
      if (item == null || id == null || id.isEmpty) continue;
      all.add(id);
      final modalities = asObject(item['architecture'])?['input_modalities'];
      if (modalities is List) {
        hasModalities = true;
        if (modalities.contains('image')) withImages.add(id);
      }
    }

    bool isEmbedding(String id) => id.toLowerCase().contains('embed');
    bool isReranker(String id) => id.toLowerCase().contains('rerank');

    final List<String> picked;
    switch (capability) {
      case Capability.embeddings:
        // A server that lists no embedding model probably has none, and
        // offering its chat models here would only produce 400s.
        picked = all.where(isEmbedding).toList();
      case Capability.vision when hasModalities:
        picked = withImages;
      case Capability.vision || Capability.chat:
        picked = all
            .where((id) => !isEmbedding(id) && !isReranker(id))
            .toList();
      case Capability.reranking:
        picked = all.where(isReranker).toList();
    }
    return picked.toSet().toList()..sort();
  }

  @override
  Future<ConnectionCheck> testConnection() async {
    if (!_endpoint.hasValidBaseUrl) {
      return const ConnectionCheck.failed('Set a valid base URL first');
    }
    if (descriptor.requiresApiKey && !_endpoint.hasApiKey) {
      return const ConnectionCheck.failed('Add an API key first');
    }
    try {
      final json = await _endpoint.get('/models');
      final count = asList(json['data']).length;
      return ConnectionCheck.ok(
        detail: count == 1 ? '1 model available' : '$count models available',
      );
    } on AiException catch (e) {
      return ConnectionCheck.failed(e.message);
    }
  }
}
