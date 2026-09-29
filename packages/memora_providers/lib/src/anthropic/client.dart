import 'package:http/http.dart' as http;
import 'package:memora_core/memora_core.dart';

import '../http/json_client.dart';
import '../shared/endpoint.dart';
import '../shared/json_read.dart';
import 'chat.dart';
import 'descriptor.dart';
import 'messages.dart';
import 'vision.dart';

/// [ProviderClient] for the Claude API.
class AnthropicClient implements ProviderClient {
  AnthropicClient(
    ProviderConfig config, {
    required http.Client httpClient,
    Duration timeout = const Duration(seconds: 120),
  }) : _endpoint = ProviderEndpoint(
         providerId: anthropicDescriptor.id,
         baseUrl: config.baseUrl ?? anthropicDescriptor.defaultBaseUrl,
         apiKey: config.apiKey,
         http: JsonClient(httpClient, timeout: timeout),
         authHeaders: (key) => {'x-api-key': key},
         extraHeaders: const {'anthropic-version': anthropicVersion},
       );

  final ProviderEndpoint _endpoint;

  @override
  ProviderDescriptor get descriptor => anthropicDescriptor;

  @override
  VisionService? vision(String modelId) =>
      AnthropicVisionService(_endpoint, modelId);

  @override
  ChatService? chat(String modelId) => AnthropicChatService(_endpoint, modelId);

  @override
  EmbeddingService? embeddings(String modelId) => null;

  @override
  RerankService? reranker(String modelId) => null;

  @override
  Future<List<String>> listModels(Capability capability) async {
    if (!descriptor.supports(capability)) return const [];
    final suggested = descriptor.suggestedModels[capability] ?? const [];
    try {
      final ids = await _modelIds();
      return ids.isEmpty ? suggested : ids;
    } on AiException {
      return suggested;
    }
  }

  /// Newest first, as the API returns them.
  Future<List<String>> _modelIds() async {
    final json = await _endpoint.get('/models?limit=1000');
    return [
      for (final raw in asList(json['data']))
        if (asString(asObject(raw)?['id']) case final id? when id.isNotEmpty)
          id,
    ];
  }

  @override
  Future<ConnectionCheck> testConnection() async {
    if (!_endpoint.hasApiKey) {
      return const ConnectionCheck.failed('Add an API key first');
    }
    try {
      final count = (await _modelIds()).length;
      return ConnectionCheck.ok(
        detail: count == 1 ? '1 model available' : '$count models available',
      );
    } on AiException catch (e) {
      return ConnectionCheck.failed(e.message);
    }
  }
}
