import 'dart:convert';

import 'package:memora_core/memora_core.dart';
import 'package:sqlite3/sqlite3.dart' hide ResultSet;

import 'codec.dart';
import 'transactions.dart';

/// [ConversationStore] on SQLite.
///
/// Messages keep their presentation and tool trace as JSON. References to
/// memories are rows in `message_references`, so deleting a memory removes
/// it from every answer that cited it.
class SqliteConversationStore implements ConversationStore {
  SqliteConversationStore(this._db);

  final Database _db;

  @override
  Future<Conversation> createConversation(
    String id,
    String title,
    DateTime now,
  ) async {
    final millis = toMillis(now);
    _db.execute(
      'INSERT INTO conversations (id, title, created_at, updated_at) '
      'VALUES (?, ?, ?, ?)',
      [id, title, millis, millis],
    );
    return Conversation(id: id, title: title, createdAt: now, updatedAt: now);
  }

  @override
  Future<List<Conversation>> listConversations() async {
    final rows = _db.select(
      'SELECT * FROM conversations ORDER BY updated_at DESC, rowid DESC',
    );
    return [for (final row in rows) _conversationFromRow(row)];
  }

  @override
  Future<Conversation?> getConversation(String id) async {
    final rows = _db.select('SELECT * FROM conversations WHERE id = ?', [id]);
    return rows.isEmpty ? null : _conversationFromRow(rows.first);
  }

  @override
  Future<List<ChatMessage>> messages(String conversationId) async {
    final references = <String, List<MessageReference>>{};
    for (final row in _db.select(
      '''
SELECT r.message_id, r.memory_id, r.relevance_score, r.position
FROM message_references r
JOIN messages msg ON msg.id = r.message_id
WHERE msg.conversation_id = ?
ORDER BY r.position, r.rowid''',
      [conversationId],
    )) {
      references
          .putIfAbsent(row['message_id'] as String, () => [])
          .add(
            MessageReference(
              memoryId: row['memory_id'] as String,
              position: row['position'] as int,
              relevance: (row['relevance_score'] as num?)?.toDouble(),
            ),
          );
    }

    final rows = _db.select(
      'SELECT * FROM messages WHERE conversation_id = ? '
      'ORDER BY created_at, rowid',
      [conversationId],
    );
    return [
      for (final row in rows)
        ChatMessage(
          id: row['id'] as String,
          conversationId: conversationId,
          role: MessageRole.fromDb(row['role'] as String),
          content: row['content'] as String,
          createdAt: fromMillis(row['created_at'] as int),
          references: references[row['id']] ?? const [],
          toolTrace: _decodeTrace(row['tool_trace'] as String?),
          presentation: _decodePresentation(row['presentation'] as String?),
          provider: row['provider'] as String?,
          model: row['model'] as String?,
        ),
    ];
  }

  /// Also moves the conversation's `updated_at` forward. References to
  /// memories that no longer exist are skipped.
  @override
  Future<void> addMessage(ChatMessage message) async {
    final presentation = message.presentation?.toJson();
    final trace = message.toolTrace.isEmpty
        ? null
        : [for (final entry in message.toolTrace) entry.toJson()];
    final createdAt = toMillis(message.createdAt);

    _db.transaction(() {
      _db.execute(
        '''
INSERT INTO messages (
  id, conversation_id, role, content, presentation, tool_trace, provider,
  model, created_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          message.id,
          message.conversationId,
          message.role.dbValue,
          message.content,
          encodeJson(presentation),
          encodeJson(trace),
          message.provider,
          message.model,
          createdAt,
        ],
      );
      if (message.references.isNotEmpty) {
        final insert = _db.prepare('''
INSERT OR IGNORE INTO message_references (
  message_id, memory_id, relevance_score, position
)
SELECT ?1, ?2, ?3, ?4
WHERE EXISTS (SELECT 1 FROM memories WHERE id = ?2)''');
        try {
          for (final reference in message.references) {
            insert.execute([
              message.id,
              reference.memoryId,
              reference.relevance,
              reference.position,
            ]);
          }
        } finally {
          insert.close();
        }
      }
      _db.execute(
        'UPDATE conversations SET updated_at = MAX(updated_at, ?) WHERE id = ?',
        [createdAt, message.conversationId],
      );
    }, immediate: true);
  }

  /// Saving a result set with an existing id replaces it.
  @override
  Future<void> saveResultSet(ResultSet resultSet) async {
    _db.execute(
      '''
INSERT INTO result_sets (
  id, conversation_id, message_id, description, memory_ids, created_at
) VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT (id) DO UPDATE SET
  conversation_id = excluded.conversation_id,
  message_id = excluded.message_id,
  description = excluded.description,
  memory_ids = excluded.memory_ids,
  created_at = excluded.created_at''',
      [
        resultSet.id,
        resultSet.conversationId,
        resultSet.messageId,
        resultSet.description,
        jsonEncode(resultSet.memoryIds),
        toMillis(resultSet.createdAt),
      ],
    );
  }

  @override
  Future<ResultSet?> latestResultSet(String conversationId) async {
    final rows = _db.select(
      'SELECT * FROM result_sets WHERE conversation_id = ? '
      'ORDER BY created_at DESC, rowid DESC LIMIT 1',
      [conversationId],
    );
    return rows.isEmpty ? null : _resultSetFromRow(rows.first);
  }

  @override
  Future<ResultSet?> getResultSet(String id) async {
    final rows = _db.select('SELECT * FROM result_sets WHERE id = ?', [id]);
    return rows.isEmpty ? null : _resultSetFromRow(rows.first);
  }

  @override
  Future<int> conversationsCiting(String memoryId) async {
    final row = _db
        .select(
          '''
SELECT COUNT(DISTINCT msg.conversation_id) AS n
FROM message_references r
JOIN messages msg ON msg.id = r.message_id
WHERE r.memory_id = ?''',
          [memoryId],
        )
        .first;
    return row['n'] as int;
  }

  /// Messages, their references and the conversation's result sets go with
  /// it through foreign key cascades.
  @override
  Future<void> deleteConversation(String id) async {
    _db.execute('DELETE FROM conversations WHERE id = ?', [id]);
  }

  static Conversation _conversationFromRow(Row row) => Conversation(
    id: row['id'] as String,
    title: row['title'] as String,
    createdAt: fromMillis(row['created_at'] as int),
    updatedAt: fromMillis(row['updated_at'] as int),
  );

  static ResultSet _resultSetFromRow(Row row) => ResultSet(
    id: row['id'] as String,
    conversationId: row['conversation_id'] as String,
    messageId: row['message_id'] as String?,
    description: row['description'] as String,
    memoryIds: [
      for (final id in decodeJson(row['memory_ids'] as String)! as List)
        id as String,
    ],
    createdAt: fromMillis(row['created_at'] as int),
  );

  static List<ToolTraceEntry> _decodeTrace(String? json) {
    final decoded = decodeJson(json);
    if (decoded is! List) return const [];
    return [
      for (final entry in decoded)
        if (entry is Map)
          ToolTraceEntry.fromJson(entry.cast<String, Object?>()),
    ];
  }

  static MessagePresentation? _decodePresentation(String? json) {
    final decoded = decodeJson(json);
    if (decoded is! Map) return null;
    return MessagePresentation.fromJson(decoded.cast<String, Object?>());
  }
}
