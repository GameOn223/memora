import 'package:memora_core/memora_core.dart';

import '../shared/endpoint.dart';
import '../shared/json_read.dart';
import '../shared/limits.dart';
import '../shared/replay_cache.dart';
import '../shared/transcript.dart';
import 'response.dart';
import 'schema.dart';

/// The model turn as Gemini sent it, plus which call ids came from Gemini.
class _ModelTurn {
  const _ModelTurn(this.parts, this.providerIds);

  final List<Object?> parts;
  final Set<String> providerIds;
}

/// Chat with function calling over `models/{model}:generateContent`.
///
/// Gemini 3 attaches a thought signature to function call parts and gives
/// each call an id. Both have to come back unchanged in the next request, so
/// the raw model turn is kept in a [TurnReplayCache].
class GeminiChatService implements ChatService {
  GeminiChatService(this._endpoint, String modelId)
    : modelId = bareModelId(modelId);

  static final _turns = TurnReplayCache<_ModelTurn>();
  static var _generatedIds = 0;

  final ProviderEndpoint _endpoint;
  final String modelId;

  @override
  Future<ChatTurn> complete(ChatRequest request) async {
    final json = await _endpoint.post('/models/$modelId:generateContent', {
      if (request.system.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': request.system},
          ],
        },
      'contents': _contents(fromFirstUserEntry(request.entries)),
      if (request.tools.isNotEmpty)
        'tools': [
          {
            'functionDeclarations': [
              for (final tool in request.tools) _declaration(tool),
            ],
          },
        ],
      'generationConfig': {
        'temperature': request.temperature,
        // Gemini 2.5 and later think by default and count it as output.
        'maxOutputTokens': request.maxOutputTokens + reasoningHeadroomTokens,
      },
    });
    return _parse(json);
  }

  static Map<String, Object?> _declaration(ToolDefinition tool) {
    final parameters = geminiSchema(tool.parameters);
    final properties = parameters['properties'];
    final hasParameters = properties is Map && properties.isNotEmpty;
    return {
      'name': tool.name,
      'description': tool.description,
      // Gemini rejects an object schema with no properties.
      if (hasParameters) 'parameters': parameters,
    };
  }

  List<Map<String, Object?>> _contents(List<ChatEntry> entries) {
    final contents = <Map<String, Object?>>[];
    final providerIds = <String>{};
    List<Object?>? pendingResponses;

    for (final entry in entries) {
      if (entry is! ToolResultEntry) pendingResponses = null;
      switch (entry) {
        case UserEntry(:final text):
          contents.add({
            'role': 'user',
            'parts': [
              {'text': text},
            ],
          });
        case AssistantEntry(:final text, :final toolCalls):
          final replay = _turns.lookup(toolCalls);
          if (replay != null) {
            providerIds.addAll(replay.providerIds);
            contents.add({'role': 'model', 'parts': replay.parts});
            continue;
          }
          final parts = [
            if (text.isNotEmpty) {'text': text},
            for (final call in toolCalls)
              {
                'functionCall': {'name': call.name, 'args': call.arguments},
              },
          ];
          if (parts.isNotEmpty) contents.add({'role': 'model', 'parts': parts});
        case ToolResultEntry(
          :final callId,
          :final toolName,
          :final content,
          :final isError,
        ):
          final decoded = decodeToolContent(content);
          final part = {
            'functionResponse': {
              if (providerIds.contains(callId)) 'id': callId,
              'name': toolName,
              'response': isError ? {'error': decoded} : {'content': decoded},
            },
          };
          // Responses to one model turn travel together in one user turn.
          if (pendingResponses == null) {
            pendingResponses = <Object?>[];
            contents.add({'role': 'user', 'parts': pendingResponses});
          }
          pendingResponses.add(part);
      }
    }
    return contents;
  }

  ChatTurn _parse(Map<String, Object?> json) {
    final candidate = firstCandidate(json);
    if (candidate == null) {
      throw AiTransientException(
        'Gemini returned no answer',
        providerId: _endpoint.providerId,
      );
    }
    final parts = candidateParts(candidate);
    final calls = <ToolCall>[];
    final providerIds = <String>{};
    for (final raw in parts) {
      final call = asObject(asObject(raw)?['functionCall']);
      final name = asString(call?['name']) ?? '';
      if (call == null || name.isEmpty) continue;
      final providerId = asString(call['id']) ?? '';
      if (providerId.isNotEmpty) providerIds.add(providerId);
      calls.add(
        ToolCall(
          id: providerId.isNotEmpty ? providerId : 'call_${++_generatedIds}',
          name: name,
          arguments: asObject(call['args']) ?? {},
        ),
      );
    }
    if (calls.isNotEmpty) {
      _turns.remember(calls, _ModelTurn(parts, providerIds));
    }

    return ChatTurn(
      text: partsText(parts),
      toolCalls: calls,
      stopReason: calls.isNotEmpty
          ? ChatStopReason.toolUse
          : switch (candidate['finishReason']) {
              'STOP' => ChatStopReason.endTurn,
              'MAX_TOKENS' => ChatStopReason.maxTokens,
              _ => ChatStopReason.other,
            },
    );
  }
}
