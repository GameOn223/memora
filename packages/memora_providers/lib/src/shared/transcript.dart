/// Trimming a chat transcript to a shape providers accept.
///
/// Memora sends a window of recent messages, so a turn can start in the
/// middle of an earlier tool loop. Both helpers return the list unchanged
/// when trimming would leave nothing to send, which keeps a broken call
/// visible as a provider error instead of an empty request.
library;

import 'package:memora_core/memora_core.dart';

/// Drops everything before the first user turn.
///
/// The Claude API and Gemini both reject a transcript whose first message
/// isn't from the user.
List<ChatEntry> fromFirstUserEntry(List<ChatEntry> entries) {
  final start = entries.indexWhere((e) => e is UserEntry);
  if (start <= 0) return entries;
  return entries.sublist(start);
}

/// Drops leading tool results whose tool call isn't in the window.
///
/// Every provider rejects a tool result that answers nothing.
List<ChatEntry> withoutOrphanToolResults(List<ChatEntry> entries) {
  final start = entries.indexWhere((e) => e is! ToolResultEntry);
  if (start <= 0) return entries;
  return entries.sublist(start);
}
