import 'dart:typed_data';

import '../model/conversation.dart';
import '../model/details.dart';
import '../model/memory.dart';
import '../model/processing.dart';
import '../model/retrieval.dart';
import '../model/understanding.dart';
import 'embedding_model.dart';

/// Sort orders offered on the browser screen.
enum MemorySort { newest, oldest, category, recentlyViewed }

/// Paging and filters for listing memories without search.
class MemoryListQuery {
  const MemoryListQuery({
    this.sort = MemorySort.newest,
    this.categories = const {},
    this.statuses = const {},
    this.takenBetween,
    this.offset = 0,
    this.limit = 200,
  });

  final MemorySort sort;
  final Set<String> categories;
  final Set<ProcessingStatus> statuses;
  final DateRange? takenBetween;
  final int offset;
  final int limit;
}

/// Count of memories for one facet value.
class FacetCount {
  const FacetCount(this.value, this.count);

  final String value;
  final int count;
}

/// Storage totals for the settings footer.
class StorageStats {
  const StorageStats({required this.memoryCount, required this.imageBytes});

  final int memoryCount;
  final int imageBytes;
}

/// Reads and writes memories and the facts derived from them.
///
/// Implemented by `memora_database`. All writes that touch AI output also
/// update the full-text index in the same transaction.
abstract interface class MemoryStore {
  /// Inserts new rows with status `captured`. Skips any whose SHA-256 exists.
  Future<InsertOutcome> insertCaptured(List<NewMemory> memories, DateTime now);

  Future<Memory?> getMemory(String id);

  Future<List<Memory>> getMemories(List<String> ids);

  Future<MemoryDetails?> getDetails(String id);

  Future<List<Memory>> listMemories(MemoryListQuery query);

  Future<List<FacetCount>> categoryCounts();

  Future<QueueSummary> queueSummary();

  Future<StorageStats> storageStats();

  /// Replaces all AI output for a memory: fields, entities, attributes,
  /// keywords and the FTS row. Does not change status.
  Future<void> saveUnderstanding(
    String id,
    MemoryUnderstanding understanding,
    NormalizedFacts facts,
    DateTime now,
  );

  Future<void> setThumbnail(String id, String thumbnailPath, DateTime now);

  Future<void> markViewed(String id, DateTime now);

  Future<void> addProcessingRecord(ProcessingRecord record);

  /// Deletes one memory and everything derived from it. Returns the files the
  /// caller must remove, or null if the memory did not exist.
  Future<MemoryFiles?> deleteMemory(String id);

  /// Deletes every memory. Returns the files the caller must remove.
  Future<List<MemoryFiles>> deleteAll();

  /// Memories without a thumbnail yet, oldest first.
  Future<List<Memory>> missingThumbnails({int limit = 50});

  /// Changes whenever any connection commits. The UI polls this to refresh.
  Future<int> dataVersion();
}

/// Typed facts produced by normalization, ready to store.
class NormalizedFacts {
  const NormalizedFacts({
    required this.entities,
    required this.attributes,
    required this.keywords,
  });

  final List<StoredEntity> entities;
  final List<StoredAttribute> attributes;
  final List<String> keywords;
}

/// A row as shown on the queue screen.
class QueueItem {
  const QueueItem({required this.memory, required this.position});

  final Memory memory;

  /// 1-based position among waiting items, or null for items not waiting.
  final int? position;
}

/// Queue bookkeeping. Implemented by `memora_database`.
abstract interface class QueueStore {
  /// Atomically claims the next claimable memory, oldest taken first, and
  /// sets it to `processing` with a lease. Returns null when nothing is due.
  Future<Memory?> claimNext(DateTime now, Duration lease);

  /// Marks a processing memory as ready and clears its lease.
  Future<void> markReady(String id, DateTime now);

  /// Returns a memory to `captured` for a later attempt.
  Future<void> releaseForRetry(
    String id, {
    required DateTime nextAttemptAt,
    required String reason,
    required DateTime now,
  });

  /// Returns a memory to `captured` and gives back the attempt it used.
  Future<void> releaseWithoutAttempt(String id, DateTime now);

  Future<void> markFailed(String id, String reason, DateTime now);

  /// User tapped Retry on a failed memory.
  Future<void> retry(String id, DateTime now);

  /// User tapped Reprocess on a ready memory.
  Future<void> requestReprocess(String id, DateTime now);

  /// Waiting, processing and failed items first, then recently finished ones.
  Future<List<QueueItem>> queueItems({int recentLimit = 20});

  /// True if anything is waiting to be claimed.
  Future<bool> hasWork(DateTime now);
}

/// Structured and full-text search. Implemented by `memora_database`.
abstract interface class SearchStore {
  /// Ids matching the query's structured filters, newest taken first.
  /// Ignores `text` and `strategies`.
  Future<List<String>> structured(RetrievalQuery query, {int limit = 500});

  /// FTS5 matches ranked by bm25, best first. Scores are positive, higher is
  /// better. [within] restricts the candidate ids.
  Future<List<ScoredId>> fullText(
    String text, {
    Set<String>? within,
    int limit = 50,
  });

  Future<List<MemoryCard>> cards(List<String> ids);

  /// Attribute values of [type] for the given memories, for aggregation.
  Future<List<AttributeValue>> attributeValues(List<String> ids, String type);

  /// Entities shared with [memoryId], used by related-memory lookups.
  Future<List<ScoredId>> sharingEntities(String memoryId, {int limit = 20});
}

/// One attribute value for aggregation and comparison tables.
class AttributeValue {
  const AttributeValue({
    required this.memoryId,
    required this.attribute,
    required this.takenAt,
  });

  final String memoryId;
  final StoredAttribute attribute;
  final DateTime takenAt;
}

/// Vector storage and nearest-neighbour search.
abstract interface class VectorStore {
  Future<void> upsert(
    String memoryId,
    Float32List vector,
    EmbeddingModelInfo model,
    DateTime now,
  );

  /// Cosine similarity search among vectors of exactly [model]. Vectors are
  /// stored normalized, so this is a dot product.
  Future<List<ScoredId>> search(
    Float32List query,
    EmbeddingModelInfo model, {
    Set<String>? within,
    int limit = 50,
  });

  Future<List<ScoredId>> neighbours(
    String memoryId,
    EmbeddingModelInfo model, {
    int limit = 10,
  });

  /// Ready memories that have no vector for [model].
  Future<List<String>> missingFor(EmbeddingModelInfo model, {int limit = 100});

  Future<int> countFor(EmbeddingModelInfo model);
}

/// Conversation history. Implemented by `memora_database`.
abstract interface class ConversationStore {
  Future<Conversation> createConversation(
    String id,
    String title,
    DateTime now,
  );

  Future<List<Conversation>> listConversations();

  Future<Conversation?> getConversation(String id);

  Future<List<ChatMessage>> messages(String conversationId);

  Future<void> addMessage(ChatMessage message);

  Future<void> saveResultSet(ResultSet resultSet);

  Future<ResultSet?> latestResultSet(String conversationId);

  Future<ResultSet?> getResultSet(String id);

  Future<int> conversationsCiting(String memoryId);

  Future<void> deleteConversation(String id);
}

/// Non-secret settings stored as JSON values.
abstract interface class SettingsStore {
  Future<Object?> read(String key);

  Future<void> write(String key, Object? value);
}

/// Encrypted key-value storage for API keys. Implemented natively with the
/// Android Keystore. Values never touch SQLite.
abstract interface class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  Future<List<String>> keys();
}
