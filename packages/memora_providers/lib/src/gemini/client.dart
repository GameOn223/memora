import 'package:http/http.dart' as http;
import 'package:memora_core/memora_core.dart';

import '../http/json_client.dart';
import '../shared/endpoint.dart';
import '../shared/json_read.dart';
import 'chat.dart';
import 'descriptor.dart';
import 'embeddings.dart';
import 'vision.dart';

/// [ProviderClient] for the Gemini API. The key travels in the
/// `x-goog-api-key` header, never in the URL.
class GeminiClient with ModelsAlwaysReady implements ProviderClient {
  GeminiClient(
    ProviderConfig config, {
    required http.Client httpClient,
    Duration timeout = const Duration(seconds: 90),
  }) : _endpoint = ProviderEndpoint(
         providerId: geminiDescriptor.id,
         baseUrl: config.baseUrl ?? geminiDescriptor.defaultBaseUrl,
         apiKey: config.apiKey,
         http: JsonClient(httpClient, timeout: timeout),
         authHeaders: (key) => {'x-goog-api-key': key},
       );

  /// Pages of the model list read before giving up on the rest.
  static const maxModelPages = 5;

  final ProviderEndpoint _endpoint;

  @override
  ProviderDescriptor get descriptor => geminiDescriptor;

  @override
  VisionService? vision(String modelId) =>
      GeminiVisionService(_endpoint, modelId);

  @override
  ChatService? chat(String modelId) => GeminiChatService(_endpoint, modelId);

  @override
  EmbeddingService? embeddings(String modelId) =>
      GeminiEmbeddingService(_endpoint, modelId);

  @override
  RerankService? reranker(String modelId) => null;

  List<String> _suggested(Capability capability) =>
      descriptor.suggestedModels[capability] ?? const [];

  @override
  Future<List<String>> listModels(Capability capability) async {
    if (!descriptor.supports(capability)) return const [];
    final methods = capability == Capability.embeddings
        ? const {'embedContent', 'batchEmbedContents'}
        : const {'generateContent'};
    try {
      final ids = <String>{};
      String? pageToken;
      for (var page = 0; page < maxModelPages; page++) {
        final json = await _endpoint.get(_modelsPath(pageToken));
        for (final raw in asList(json['models'])) {
          final model = asObject(raw);
          final name = asString(model?['name']);
          final supported = asList(model?['supportedGenerationMethods']);
          if (name == null || !supported.any(methods.contains)) continue;
          ids.add(name.startsWith('models/') ? name.substring(7) : name);
        }
        pageToken = asString(json['nextPageToken']);
        if (pageToken == null || pageToken.isEmpty) break;
      }
      return ids.isEmpty ? _suggested(capability) : (ids.toList()..sort());
    } on AiException {
      return _suggested(capability);
    }
  }

  static String _modelsPath(String? pageToken) => pageToken == null
      ? '/models?pageSize=1000'
      : '/models?pageSize=1000&pageToken=${Uri.encodeQueryComponent(pageToken)}';

  @override
  Future<ConnectionCheck> testConnection() async {
    if (!_endpoint.hasApiKey) {
      return const ConnectionCheck.failed('Add an API key first');
    }
    try {
      final json = await _endpoint.get(_modelsPath(null));
      final count = asList(json['models']).length;
      final more = (asString(json['nextPageToken']) ?? '').isNotEmpty;
      return ConnectionCheck.ok(
        detail: more
            ? 'At least $count models available'
            : '$count models available',
      );
    } on AiException catch (e) {
      return ConnectionCheck.failed(e.message);
    }
  }
}
