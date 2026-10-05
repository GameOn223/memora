import 'package:meta/meta.dart';

@immutable
class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.pinned = false,
  });

  final String id;
  final String title;
  final DateTime createdAt;

  /// Moves forward when a message is added, which is what orders the
  /// conversation list. Renaming and pinning leave it alone.
  final DateTime updatedAt;

  /// Kept at the top of the conversation list by the user.
  final bool pinned;

  Conversation copyWith({String? title, DateTime? updatedAt, bool? pinned}) =>
      Conversation(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        pinned: pinned ?? this.pinned,
      );
}

enum MessageRole {
  user('user'),
  assistant('assistant');

  const MessageRole(this.dbValue);

  final String dbValue;

  static MessageRole fromDb(String value) =>
      value == 'assistant' ? assistant : user;
}

/// A memory cited by an assistant message.
@immutable
class MessageReference {
  const MessageReference({
    required this.memoryId,
    required this.position,
    this.relevance,
  });

  final String memoryId;

  /// Order in the sources list, starting at 0.
  final int position;

  /// 0 to 1 when known.
  final double? relevance;
}

/// One tool call the chat agent made, kept for "How this was found".
@immutable
class ToolTraceEntry {
  const ToolTraceEntry({
    required this.tool,
    required this.arguments,
    required this.summary,
  });

  factory ToolTraceEntry.fromJson(Map<String, Object?> json) => ToolTraceEntry(
    tool: json['tool'] as String? ?? '',
    arguments: (json['arguments'] as Map?)?.cast<String, Object?>() ?? const {},
    summary: json['summary'] as String? ?? '',
  );

  final String tool;
  final Map<String, Object?> arguments;

  /// Short result description, for example `8 candidates`.
  final String summary;

  Map<String, Object?> toJson() => {
    'tool': tool,
    'arguments': arguments,
    'summary': summary,
  };

  /// A one-line rendering such as `search_by_entity(value: "Reliance") · 8`.
  String get display {
    final args = arguments.entries
        .map((e) => '${e.key}: ${e.value is String ? '"${e.value}"' : e.value}')
        .join(', ');
    return summary.isEmpty ? '$tool($args)' : '$tool($args) · $summary';
  }
}

/// How sources are shown under an answer. See docs/architecture.md, section 9.3.
enum SourceLayout {
  strip('strip'),
  table('table');

  const SourceLayout(this.key);

  final String key;

  static SourceLayout fromKey(String? key) => key == 'table' ? table : strip;
}

/// Whether a large figure was checked against the original image.
enum VerificationState {
  none('none'),
  verified('verified'),
  corrected('corrected');

  const VerificationState(this.key);

  final String key;

  static VerificationState fromKey(String? key) =>
      values.firstWhere((v) => v.key == key, orElse: () => none);
}

/// Display hints stored with an assistant message.
@immutable
class MessagePresentation {
  const MessagePresentation({
    this.layout = SourceLayout.strip,
    this.headline,
    this.headlineNote,
    this.tableAttribute,
    this.highlightMemoryId,
    this.sourceLabel,
    this.verification = VerificationState.none,
    this.searchOnly = false,
  });

  factory MessagePresentation.fromJson(Map<String, Object?> json) =>
      MessagePresentation(
        layout: SourceLayout.fromKey(json['layout'] as String?),
        headline: json['headline'] as String?,
        headlineNote: json['headline_note'] as String?,
        tableAttribute: json['table_attribute'] as String?,
        highlightMemoryId: json['highlight_memory_id'] as String?,
        sourceLabel: json['source_label'] as String?,
        verification: VerificationState.fromKey(
          json['verification'] as String?,
        ),
        searchOnly: json['search_only'] as bool? ?? false,
      );

  final SourceLayout layout;

  /// A large figure shown above the sources, for example `₹2,103`.
  final String? headline;

  /// Small caption under the headline.
  final String? headlineNote;

  /// For table layout, which attribute fills the value column.
  final String? tableAttribute;

  /// Source row or card to highlight, such as the maximum.
  final String? highlightMemoryId;

  /// Caption above the sources, for example `8 memories · entity + semantic`.
  final String? sourceLabel;
  final VerificationState verification;

  /// True when no chat model was available and the reply came from search.
  final bool searchOnly;

  Map<String, Object?> toJson() => {
    'layout': layout.key,
    'headline': ?headline,
    'headline_note': ?headlineNote,
    'table_attribute': ?tableAttribute,
    'highlight_memory_id': ?highlightMemoryId,
    'source_label': ?sourceLabel,
    'verification': verification.key,
    'search_only': searchOnly,
  };
}

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.references = const [],
    this.toolTrace = const [],
    this.presentation,
    this.provider,
    this.model,
  });

  final String id;
  final String conversationId;
  final MessageRole role;
  final String content;
  final DateTime createdAt;
  final List<MessageReference> references;
  final List<ToolTraceEntry> toolTrace;
  final MessagePresentation? presentation;
  final String? provider;
  final String? model;
}

/// Memories returned by a search in a conversation. The newest one is the
/// active set that follow-up questions narrow or aggregate.
@immutable
class ResultSet {
  const ResultSet({
    required this.id,
    required this.conversationId,
    required this.description,
    required this.memoryIds,
    required this.createdAt,
    this.messageId,
  });

  final String id;
  final String conversationId;
  final String? messageId;
  final String description;
  final List<String> memoryIds;
  final DateTime createdAt;
}
