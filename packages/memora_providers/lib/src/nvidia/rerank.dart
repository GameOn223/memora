import 'package:http/http.dart' as http;
import 'package:memora_core/memora_core.dart';

import '../http/json_client.dart';
import '../shared/json_read.dart';

/// NVIDIA's hosted reranking endpoint for [modelId].
///
/// Current models have their own path, with dots in the name written as
/// underscores. The original `nvidia/rerank-qa-mistral-4b` used a shared one.
Uri nvidiaRerankUrl(String modelId) {
  const shared = {'nvidia/rerank-qa-mistral-4b', 'nv-rerank-qa-mistral-4b:1'};
  if (shared.contains(modelId)) {
    return Uri.parse('https://ai.api.nvidia.com/v1/retrieval/nvidia/reranking');
  }
  final path = modelId.replaceAll('.', '_');
  return Uri.parse('https://ai.api.nvidia.com/v1/retrieval/$path/reranking');
}

/// Reranking with NVIDIA NeMo Retriever models.
class NvidiaRerankService implements RerankService {
  NvidiaRerankService({
    required http.Client httpClient,
    required this._apiKey,
    required this.modelId,
    Duration timeout = const Duration(seconds: 90),
  }) : _http = JsonClient(httpClient, timeout: timeout);

  static const providerId = 'nvidia';

  final JsonClient _http;
  final String? _apiKey;
  final String modelId;

  @override
  Future<List<RerankScore>> rerank(
    String query,
    List<RerankCandidate> candidates,
  ) async {
    if (candidates.isEmpty) return const [];
    final key = _apiKey ?? '';
    final json = await _http.post(
      nvidiaRerankUrl(modelId),
      {
        'model': modelId,
        'query': {'text': query},
        'passages': [
          for (final candidate in candidates) {'text': candidate.text},
        ],
        'truncate': 'END',
      },
      headers: {if (key.isNotEmpty) 'authorization': 'Bearer $key'},
      providerId: providerId,
    );

    final logits = <int, double>{};
    for (final raw in asList(json['rankings'])) {
      final ranking = asObject(raw);
      final index = ranking?['index'];
      final logit = ranking?['logit'];
      if (index is int &&
          index >= 0 &&
          index < candidates.length &&
          logit is num) {
        logits[index] = logit.toDouble();
      }
    }
    if (logits.isEmpty) {
      throw const AiTransientException(
        'NVIDIA returned no rankings',
        providerId: providerId,
      );
    }

    final scores = [
      for (final e in logits.entries)
        RerankScore(candidates[e.key].id, e.value),
    ]..sort((a, b) => b.score.compareTo(a.score));
    // The contract promises a score for every candidate, so anything the
    // service left out goes last, in its original order.
    final floor = scores.last.score - 1;
    for (var i = 0; i < candidates.length; i++) {
      if (!logits.containsKey(i)) {
        scores.add(RerankScore(candidates[i].id, floor));
      }
    }
    return scores;
  }
}
