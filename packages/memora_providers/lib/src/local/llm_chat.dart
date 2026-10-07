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
class LocalLlmChatService implements StreamingChatService {
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
  Stream<ChatStreamEvent> stream(ChatRequest request) async* {
    final collected = StringBuffer();
    // Text is only worth showing as it arrives when it is the answer. A
    // reply that turns out to be a tool call is not shown at all, so the
    // pieces are held until the shape of the turn is known.
    final offered = {for (final tool in request.tools) tool.name};
    final streamable = offered.isEmpty || _hasSearched(request.entries);
    await for (final piece in _session.runStreaming(
      LocalLlmPrompt.chat(request),
      capability: Capability.chat,
      maxOutputTokens: request.maxOutputTokens,
    )) {
      collected.write(piece);
      if (streamable) yield ChatTextDelta(piece);
    }
    yield ChatTurnDone(_turnFor(collected.toString(), request));
  }

  @override
  Future<ChatTurn> complete(ChatRequest request) async => _turnFor(
    await _session.run(
      LocalLlmPrompt.chat(request),
      capability: Capability.chat,
      maxOutputTokens: request.maxOutputTokens,
    ),
    request,
  );

  /// Reads [reply] as either a tool call or an answer.
  ChatTurn _turnFor(String reply, ChatRequest request) {
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
    // Tools were offered and none was called. For a question about their
    // own memories that is the model failing to search rather than choosing
    // not to, and the two look identical from here, so the question decides.
    // A plainly general question gets the plain answer it asked for.
    if (offered.isNotEmpty &&
        !_hasSearched(request.entries) &&
        QuestionKind.needsMemories(_lastQuestion(request.entries))) {
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

  /// The question this turn is answering, which is the last thing the user
  /// said. Empty when there is nothing to go on, which reads as general.
  static String _lastQuestion(List<ChatEntry> entries) {
    for (final entry in entries.reversed) {
      if (entry is UserEntry) return entry.text;
    }
    return '';
  }

  static bool _hasSearched(List<ChatEntry> entries) =>
      entries.any((e) => e is ToolResultEntry && !e.isError);
}
