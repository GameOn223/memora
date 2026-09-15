import 'package:memora_core/memora_core.dart';

import '../shared/endpoint.dart';
import '../shared/json_read.dart';
import '../shared/limits.dart';
import '../shared/replay_cache.dart';
import 'messages.dart';

/// Chat with tool use over `POST /messages`.
///
/// No temperature is sent: current models reject sampling settings other
/// than the defaults. Models that think by default return signed thinking
/// blocks, which must come back unchanged while a tool loop continues, so
/// the assistant content is kept in a [TurnReplayCache].
class AnthropicChatService implements ChatService {
  AnthropicChatService(this._endpoint, this.modelId);

  static final _turns = TurnReplayCache<List<Object?>>();

  final ProviderEndpoint _endpoint;
  final String modelId;

  @override
  Future<ChatTurn> complete(ChatRequest request) async {
    final messages = MessageListBuilder();
    for (final entry in request.entries) {
      switch (entry) {
        case UserEntry(:final text):
          messages.add('user', [
            if (text.isNotEmpty) {'type': 'text', 'text': text},
          ]);
        case AssistantEntry(:final text, :final toolCalls):
          messages.add(
            'assistant',
            _turns.lookup(toolCalls) ??
                [
                  if (text.isNotEmpty) {'type': 'text', 'text': text},
                  for (final call in toolCalls)
                    {
                      'type': 'tool_use',
                      'id': call.id,
                      'name': call.name,
                      'input': call.arguments,
                    },
                ],
          );
        case ToolResultEntry(:final callId, :final content, :final isError):
          messages.add('user', [
            {
              'type': 'tool_result',
              'tool_use_id': callId,
              'content': content,
              if (isError) 'is_error': true,
            },
          ]);
      }
    }

    final json = await _endpoint.post('/messages', {
      'model': modelId,
      'max_tokens': request.maxOutputTokens + reasoningHeadroomTokens,
      if (request.system.isNotEmpty) 'system': request.system,
      'messages': messages.build(),
      if (request.tools.isNotEmpty)
        'tools': [
          for (final tool in request.tools)
            {
              'name': tool.name,
              'description': tool.description,
              'input_schema': tool.parameters,
            },
        ],
    });
    return _parse(json);
  }

  ChatTurn _parse(Map<String, Object?> json) {
    final content = asList(json['content']);
    final calls = <ToolCall>[];
    for (final raw in content) {
      final block = asObject(raw);
      if (block?['type'] != 'tool_use') continue;
      final id = asString(block?['id']) ?? '';
      final name = asString(block?['name']) ?? '';
      if (id.isEmpty || name.isEmpty) continue;
      calls.add(
        ToolCall(
          id: id,
          name: name,
          arguments: asObject(block?['input']) ?? {},
        ),
      );
    }
    if (calls.isNotEmpty) _turns.remember(calls, content);

    return ChatTurn(
      text: responseText(content),
      toolCalls: calls,
      stopReason: switch (json['stop_reason']) {
        _ when calls.isNotEmpty => ChatStopReason.toolUse,
        'end_turn' || 'stop_sequence' => ChatStopReason.endTurn,
        'max_tokens' => ChatStopReason.maxTokens,
        _ => ChatStopReason.other,
      },
    );
  }
}
