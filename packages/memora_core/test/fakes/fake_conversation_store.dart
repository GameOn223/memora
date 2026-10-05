import 'package:memora_core/memora_core.dart';

import 'fake_memora_state.dart';

/// In-memory [ConversationStore]. References to deleted memories disappear,
/// as they would through the foreign key cascade.
mixin FakeConversationStore on FakeMemoraState implements ConversationStore {
  @override
  Future<Conversation> createConversation(
    String id,
    String title,
    DateTime now,
  ) async {
    final conversation = Conversation(
      id: id,
      title: title,
      createdAt: now,
      updatedAt: now,
    );
    conversationRows[id] = conversation;
    touch();
    return conversation;
  }

  @override
  Future<List<Conversation>> listConversations() async =>
      conversationRows.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<Conversation?> getConversation(String id) async =>
      conversationRows[id];

  @override
  Future<List<ChatMessage>> messages(String conversationId) async => [
    for (final m in messageRows)
      if (m.conversationId == conversationId) m,
  ];

  @override
  Future<void> addMessage(ChatMessage message) async {
    if (failAssistantMessages && message.role == MessageRole.assistant) {
      throw StateError('database is locked');
    }
    final conversation = conversationRows[message.conversationId];
    if (conversation == null) {
      throw StateError('No conversation ${message.conversationId}');
    }
    messageRows.add(message);
    conversationRows[conversation.id] = Conversation(
      id: conversation.id,
      title: conversation.title,
      createdAt: conversation.createdAt,
      updatedAt: message.createdAt,
    );
    touch();
  }

  @override
  Future<void> saveResultSet(ResultSet resultSet) async {
    resultSetRows.add(resultSet);
    touch();
  }

  @override
  Future<ResultSet?> latestResultSet(String conversationId) async {
    ResultSet? latest;
    for (final set in resultSetRows) {
      if (set.conversationId != conversationId) continue;
      if (latest == null || !set.createdAt.isBefore(latest.createdAt)) {
        latest = set;
      }
    }
    return latest;
  }

  @override
  Future<ResultSet?> getResultSet(String id) async {
    for (final set in resultSetRows) {
      if (set.id == id) return set;
    }
    return null;
  }

  @override
  Future<int> conversationsCiting(String memoryId) async => {
    for (final m in messageRows)
      if (m.references.any((r) => r.memoryId == memoryId)) m.conversationId,
  }.length;

  @override
  Future<void> deleteConversation(String id) async {
    conversationRows.remove(id);
    messageRows.removeWhere((m) => m.conversationId == id);
    resultSetRows.removeWhere((s) => s.conversationId == id);
    touch();
  }
}
