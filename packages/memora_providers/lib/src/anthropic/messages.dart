import '../shared/json_read.dart';

/// Version header value sent with every request.
const anthropicVersion = '2023-06-01';

/// Builds a `messages` array, merging consecutive turns from the same role
/// into one message. The API wants every tool result for one assistant turn
/// in a single user message, ahead of any text.
class MessageListBuilder {
  final List<Map<String, Object?>> _messages = [];

  void add(String role, List<Object?> blocks) {
    if (blocks.isEmpty) return;
    final last = _messages.isEmpty ? null : _messages.last;
    if (last != null && last['role'] == role) {
      (last['content']! as List<Object?>).addAll(blocks);
    } else {
      _messages.add({
        'role': role,
        'content': <Object?>[...blocks],
      });
    }
  }

  List<Map<String, Object?>> build() => _messages;
}

/// Joined text of the `text` blocks in a response.
String responseText(List<Object?> content) {
  final buffer = StringBuffer();
  for (final raw in content) {
    final block = asObject(raw);
    if (block?['type'] == 'text') buffer.write(asString(block?['text']) ?? '');
  }
  return buffer.toString();
}
