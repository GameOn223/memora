import 'package:memora_core/memora_core.dart';

import 'llm_prompt.dart';
import 'llm_session.dart';
import 'model_catalog.dart';

/// Chat with a Gemma model running on this phone.
///
/// ## Tool calling on a small model
///
/// Ask works by letting the model call read-only search tools and answering
/// from what comes back. A 1B model offered eleven tools gets it right some
/// of the time: it writes prose where a call belongs, invents a tool name,
/// or answers from nothing at all. Inventing an answer about someone's own
/// bills is the one outcome worth avoiding, so:
///
/// - The reply is read leniently. JSON in a fenced block or wrapped in a
///   sentence still counts, and the argument keys can be `arguments`,
///   `args`, `parameters` or `input`.
/// - The tool name has to be one that was offered. A call to something
///   invented is not a call.
/// - When tools were offered, nothing has been searched yet and no usable
///   call came back, the turn is handed to the deterministic search answer
///   through [ToolCallingUnavailableException]. The user gets "Found 3
///   memories matching reliance" rather than a confident sentence the model
///   made up.
/// - Once a tool result is in the transcript, plain text is the answer. It
///   is grounded in what the tool returned, which is the point of the loop.
class LocalLlmChatService implements ChatService {
  LocalLlmChatService({
    required LocalLlmRuntime runtime,
    required LocalLlmFiles files,
    required this.spec,
  }) : _session = LocalLlmSession(runtime: runtime, files: files, spec: spec);

  static const providerId = 'local';

  /// Tool call ids, which the on-device model never provides itself.
  static var _callCount = 0;

  final LocalLlmSession _session;
  final LocalLlmSpec spec;

  @override
  Future<ChatTurn> complete(ChatRequest request) async {
    final reply = await _session.run(
      LocalLlmPrompt.chat(request),
      capability: Capability.chat,
      maxOutputTokens: request.maxOutputTokens,
    );
    final offered = {for (final tool in request.tools) tool.name};
    final call = offered.isEmpty
        ? null
        : parseLocalToolCall(reply, offered, id: 'local_${++_callCount}');
    if (call != null) {
      return ChatTurn(
        text: '',
        toolCalls: [call],
        stopReason: ChatStopReason.toolUse,
      );
    }
    if (offered.isNotEmpty && !_hasSearched(request.entries)) {
      throw ToolCallingUnavailableException(
        providerId: providerId,
        modelId: spec.id,
      );
    }
    return ChatTurn(
      text: reply,
      toolCalls: const [],
      stopReason: ChatStopReason.endTurn,
    );
  }

  static bool _hasSearched(List<ChatEntry> entries) =>
      entries.any((e) => e is ToolResultEntry && !e.isError);
}
