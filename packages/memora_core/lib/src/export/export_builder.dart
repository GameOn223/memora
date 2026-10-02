import 'package:meta/meta.dart';

import '../ai/errors.dart';
import '../ai/router.dart';
import '../model/details.dart';
import '../model/memory.dart';
import '../ports/embedding_model.dart';
import '../ports/platform.dart';
import '../ports/stores.dart';

/// Looks up the embedding models whose vectors should be described in an
/// export. Vectors themselves are never exported.
typedef EmbeddingModelsLookup = Future<List<EmbeddingModelInfo>> Function();

/// The `manifest.json` at the root of an export. See docs/export-format.md.
@immutable
class ExportManifest {
  const ExportManifest({
    required this.exportedAt,
    required this.appVersion,
    required this.memoryCount,
    required this.conversationCount,
  });

  static const formatName = 'memora-export';

  /// Bumped only when the format changes in a way readers must notice.
  static const formatVersion = 1;

  final DateTime exportedAt;
  final String appVersion;
  final int memoryCount;
  final int conversationCount;

  Map<String, Object?> toJson() => {
    'format': formatName,
    'format_version': formatVersion,
    'exported_at': _timestamp(exportedAt)!,
    'app_version': appVersion,
    'counts': {
      'memories': memoryCount,
      'conversations': conversationCount,
      'images': memoryCount,
    },
  };
}

/// One line of `memories.jsonl`, plus where its image comes from and goes.
@immutable
class ExportMemoryRecord {
  const ExportMemoryRecord({
    required this.details,
    required this.imageFile,
    this.embeddings = const [],
  });

  final MemoryDetails details;

  /// Path inside the export, such as `images/9f2c.png`.
  final String imageFile;

  /// Embedding models that hold a vector for this memory.
  final List<EmbeddingModelInfo> embeddings;

  Memory get memory => details.memory;

  /// Where the image lives in app storage, relative to the files directory.
  String get sourcePath => memory.imagePath;

  Map<String, Object?> toJson() => {
    'id': memory.id,
    'image_file': imageFile,
    'source_path': memory.imagePath,
    'thumbnail_path': ?memory.thumbnailPath,
    'source': memory.source.dbValue,
    'sha256': memory.sha256,
    'mime_type': memory.mimeType,
    'width': memory.width,
    'height': memory.height,
    'byte_size': memory.byteSize,
    'taken_at': _timestamp(memory.takenAt)!,
    'added_at': _timestamp(memory.addedAt)!,
    'updated_at': _timestamp(memory.updatedAt)!,
    'processed_at': ?_timestamp(memory.processedAt),
    'last_viewed_at': ?_timestamp(memory.lastViewedAt),
    'status': memory.status.dbValue,
    'attempts': memory.attempts,
    'failure_reason': ?memory.failureReason,
    'summary': ?memory.summary,
    'category': ?memory.category,
    'visual_description': ?memory.visualDescription,
    'extracted_text': ?memory.extractedText,
    'entities': [
      for (final e in details.entities)
        {
          'type': e.type,
          'value': e.value,
          'normalized_value': e.normalizedValue,
        },
    ],
    'attributes': [
      for (final a in details.attributes)
        {
          'type': a.type,
          'value': a.value,
          'value_num': ?a.valueNum,
          'value_date': ?a.valueDate,
          'currency': ?a.currency,
          'label': ?a.label,
        },
    ],
    'keywords': details.keywords,
    'processing': [
      for (final p in details.processing)
        {
          'capability': p.capability.key,
          'provider': p.provider,
          'model': p.model,
          'version': ?p.version,
          'status': p.outcome.dbValue,
          'latency_ms': ?p.latency?.inMilliseconds,
          'error': ?p.error,
          'created_at': _timestamp(p.createdAt)!,
        },
    ],
    'embeddings': [
      for (final e in embeddings)
        {
          'model_id': e.storageId,
          'version': e.version,
          'dimensions': e.dimensions,
        },
    ],
  };
}

/// Builds the records for "Export all memories". The app writes them into a
/// zip through the Storage Access Framework. See docs/export-format.md.
class ExportBuilder {
  /// [embeddingModels] is required so an export can't quietly leave out its
  /// embedding metadata. Pass [noEmbeddingModels] when there really is none.
  ExportBuilder({
    required this._memories,
    required this._conversations,
    required this._vectors,
    required this._clock,
    required this._embeddingModels,
    this._appVersion = '0.1.0',
  });

  /// How many memories are read from the database at a time.
  static const pageSize = 200;

  final MemoryStore _memories;
  final ConversationStore _conversations;
  final VectorStore _vectors;
  final Clock _clock;
  final String _appVersion;
  final EmbeddingModelsLookup _embeddingModels;

  /// For an export made with no embedding model configured at all.
  static Future<List<EmbeddingModelInfo>> noEmbeddingModels() async => const [];

  /// The active embedding model, for an export that should describe the
  /// vectors it is leaving behind.
  static EmbeddingModelsLookup activeEmbeddingModel(CapabilityRouter router) {
    return () async {
      try {
        return [(await router.embeddings()).service.model];
      } on CapabilityUnavailableException {
        return const [];
      }
    };
  }

  Future<ExportManifest> manifest() async {
    final stats = await _memories.storageStats();
    final conversations = await _conversations.listConversations();
    return ExportManifest(
      exportedAt: _clock.now(),
      appVersion: _appVersion,
      memoryCount: stats.memoryCount,
      conversationCount: conversations.length,
    );
  }

  /// Every memory, oldest first, with its entities, attributes, keywords,
  /// processing records and embedding metadata.
  Stream<ExportMemoryRecord> memories() async* {
    final models = await _embeddingModels();
    final missing = <EmbeddingModelInfo, Set<String>>{};
    for (final model in models) {
      missing[model] = (await _vectors.missingFor(
        model,
        limit: 1 << 30,
      )).toSet();
    }

    var offset = 0;
    while (true) {
      final page = await _memories.listMemories(
        MemoryListQuery(
          sort: MemorySort.oldest,
          offset: offset,
          limit: pageSize,
        ),
      );
      if (page.isEmpty) return;
      for (final memory in page) {
        final details = await _memories.getDetails(memory.id);
        if (details == null) continue;
        yield ExportMemoryRecord(
          details: details,
          imageFile: 'images/${memory.id}.${_extension(memory)}',
          embeddings: [
            for (final model in models)
              if (memory.status == ProcessingStatus.ready &&
                  !(missing[model] ?? const {}).contains(memory.id))
                model,
          ],
        );
      }
      if (page.length < pageSize) return;
      offset += page.length;
    }
  }

  /// Every conversation with its messages, sources and active result set.
  Stream<Map<String, Object?>> conversations() async* {
    for (final conversation in await _conversations.listConversations()) {
      final messages = await _conversations.messages(conversation.id);
      final active = await _conversations.latestResultSet(conversation.id);
      yield {
        'id': conversation.id,
        'title': conversation.title,
        'created_at': _timestamp(conversation.createdAt)!,
        'updated_at': _timestamp(conversation.updatedAt)!,
        'messages': [
          for (final message in messages)
            {
              'id': message.id,
              'role': message.role.dbValue,
              'content': message.content,
              'created_at': _timestamp(message.createdAt)!,
              'provider': ?message.provider,
              'model': ?message.model,
              'presentation': ?message.presentation?.toJson(),
              if (message.toolTrace.isNotEmpty)
                'tool_trace': [
                  for (final entry in message.toolTrace) entry.toJson(),
                ],
              if (message.references.isNotEmpty)
                'references': [
                  for (final reference in message.references)
                    {
                      'memory_id': reference.memoryId,
                      'position': reference.position,
                      'relevance': ?reference.relevance,
                    },
                ],
            },
        ],
        'active_result_set': ?active == null
            ? null
            : {
                'id': active.id,
                'message_id': ?active.messageId,
                'description': active.description,
                'memory_ids': active.memoryIds,
                'created_at': _timestamp(active.createdAt)!,
              },
      };
    }
  }

  static const _extensions = {
    'image/png': 'png',
    'image/jpeg': 'jpg',
    'image/jpg': 'jpg',
    'image/webp': 'webp',
    'image/gif': 'gif',
    'image/heic': 'heic',
    'image/heif': 'heif',
    'image/avif': 'avif',
  };

  String _extension(Memory memory) {
    final path = memory.imagePath;
    final dot = path.lastIndexOf('.');
    if (dot > 0 && dot < path.length - 1) {
      final extension = path.substring(dot + 1).toLowerCase();
      if (RegExp(r'^[a-z0-9]{1,5}$').hasMatch(extension)) return extension;
    }
    return _extensions[memory.mimeType.toLowerCase()] ?? 'bin';
  }
}

String? _timestamp(DateTime? value) => value?.toUtc().toIso8601String();
