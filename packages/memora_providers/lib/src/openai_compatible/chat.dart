import 'dart:convert';

import 'package:memora_core/memora_core.dart';

import '../shared/endpoint.dart';
import '../shared/json_read.dart';
import '../shared/limits.dart';
import '../shared/replay_cache.dart';
import 'message_text.dart';
import 'presets.dart';

/// Chat with tool calls over `POST /chat/completions`.
class OpenAiChatService implements ChatService {
  OpenAiChatService(this._endpoint, this._profile, this.modelId);

  /// OpenRouter `reasoning_details` by tool call ids.
  static final _reasoningDetails = TurnReplayCache<Object>();
  static var _generatedIds = 0;

  final ProviderEndpoint _endpoint;
  final OpenAiCompatibleProfile _profile;
  final String modelId;

  @override
  Future<ChatTurn> complete(ChatRequest request) async {
    final reasoning = isOpenAiReasoningModel(modelId);
    final json = await _endpoint.post('/chat/completions', {
      'model': modelId,
      'messages': [
        if (request.system.isNotEmpty)
          {'role': 'system', 'content': request.system},
        for (final entry in request.entries) _message(entry),
      ],
      if (request.tools.isNotEmpty)
        'tools': [
          for (final tool in request.tools)
            {
              'type': 'function',
              'function': {
                'name': tool.name,
                'description': tool.description,
                'parameters': tool.parameters,
              },
            },
        ],
      if (!reasoning) 'temperature': request.temperature,
      _profile.maxTokensField: reasoning
          ? request.maxOutputTokens + reasoningHeadroomTokens
          : request.maxOutputTokens,
    });
    return _parse(json);
  }

  Map<String, Object?> _message(ChatEntry entry) {
    switch (entry) {
      case UserEntry(:final text):
        return {'role': 'user', 'content': text};
      case AssistantEntry(:final text, :final toolCalls):
        final details = _reasoningDetails.lookup(toolCalls);
        return {
          'role': 'assistant',
          'content': text.isEmpty && toolCalls.isNotEmpty ? null : text,
          if (toolCalls.isNotEmpty)
            'tool_calls': [
              for (final call in toolCalls)
                {
                  'id': call.id,
                  'type': 'function',
                  'function': {
                    'name': call.name,
                    'arguments': jsonEncode(call.arguments),
                  },
                },
            ],
          'reasoning_details': ?details,
        };
      case ToolResultEntry(:final callId, :final content):
        return {'role': 'tool', 'tool_call_id': callId, 'content': content};
    }
  }

  ChatTurn _parse(Map<String, Object?> json) {
    final choices = asList(json['choices']);
    final choice = choices.isEmpty ? null : asObject(choices.first);
    if (choice == null) {
      throw AiTransientException(
        'The provider returned no answer',
        providerId: _endpoint.providerId,
      );
    }
    final message = asObject(choice['message']) ?? const {};

    final calls = <ToolCall>[];
    for (final raw in asList(message['tool_calls'])) {
      final call = asObject(raw);
      final function = asObject(call?['function']);
      final name = asString(function?['name']) ?? '';
      if (call == null || name.isEmpty) continue;
      final id = asString(call['id']) ?? '';
      calls.add(
        ToolCall(
          id: id.isEmpty ? 'call_${++_generatedIds}' : id,
          name: name,
          arguments: decodeArguments(function?['arguments']),
        ),
      );
    }

    final details = message['reasoning_details'];
    if (calls.isNotEmpty && details is List && details.isNotEmpty) {
      _reasoningDetails.remember(calls, details);
    }

    final refusal = asString(message['refusal']);
    final text = messageText(message['content']);
    return ChatTurn(
      text: text.isEmpty && refusal != null ? refusal : text,
      toolCalls: calls,
      stopReason: calls.isNotEmpty
          ? ChatStopReason.toolUse
          : switch (choice['finish_reason']) {
              'stop' => ChatStopReason.endTurn,
              'length' => ChatStopReason.maxTokens,
              _ => ChatStopReason.other,
            },
    );
  }
}
