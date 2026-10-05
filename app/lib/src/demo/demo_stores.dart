import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

import 'demo_data.dart';
import 'demo_images.dart';

/// Shared in-memory state behind every demo store, so a write through one
/// store is visible through the others and bumps the data version.
class DemoDatabase {
  DemoDatabase(this.clock);

  final Clock clock;
  final Map<String, Memory> memories = {};
  final Map<String, List<StoredEntity>> entities = {};
  final Map<String, List<StoredAttribute>> attributes = {};
  final Map<String, List<String>> keywords = {};
  final Map<String, List<ProcessingRecord>> processing = {};
  final Map<String, int> citationOverrides = {};

  /// Image paths and the synthetic picture drawn for each.
  final Map<String, (DemoImageKind, int)> images = {};
  final Map<String, Conversation> conversations = {};
  final Map<String, List<ChatMessage>> messages = {};
  final List<ResultSet> resultSets = [];
  int version = 1;
  int _ids = 0;

  void touch() => version++;

  String nextId(String prefix) => '$prefix-${++_ids}';

  /// Local date and time [daysAgo] calendar days before now at `HH:mm`.
  DateTime at(int daysAgo, String time) {
    final now = clock.now();
    final [h, m] = time.split(':').map(int.parse).toList();
    return DateTime(now.year, now.month, now.day - daysAgo, h, m);
  }

  void seedMemories() {
    for (final spec in demoMemorySpecs) {
      final taken = at(spec.daysAgo, spec.time);
      final added = spec.added == null
          ? taken.add(const Duration(minutes: 1))
          : at(spec.added!.$1, spec.added!.$2);
      final processed = spec.processed == null
          ? null
          : at(spec.processed!.$1, spec.processed!.$2);
      final imagePath = 'originals/${spec.id}.png';
      final thumbPath = 'thumbnails/${spec.id}.webp';
      images[imagePath] = (spec.kind, spec.seed);
      images[thumbPath] = (spec.kind, spec.seed);
      memories[spec.id] = Memory(
        id: spec.id,
        imagePath: imagePath,
        thumbnailPath: thumbPath,
        source: MemorySource.gallery,
        sha256: 'sha-${spec.id}',
        mimeType: 'image/png',
        width: 1080,
        height: 2400,
        byteSize: spec.byteSize,
        takenAt: taken,
        addedAt: added,
        updatedAt: processed ?? added,
        status: spec.status,
        summary: spec.summary,
        visualDescription: spec.description.isEmpty ? null : spec.description,
        category: spec.category,
        failureReason: spec.failureReason,
        attempts: spec.status == ProcessingStatus.failed ? 3 : 0,
        processedAt: processed,
      );
      entities[spec.id] = [...spec.entities];
      attributes[spec.id] = [...spec.attributes];
      keywords[spec.id] = [...spec.keywords];
      if (spec.conversationCount != null) {
        citationOverrides[spec.id] = spec.conversationCount!;
      }
      processing[spec.id] = [
        if (processed != null) ...[
          ProcessingRecord(
            memoryId: spec.id,
            capability: Capability.embeddings,
            provider: 'local',
            model: 'bge-small-en-v1.5',
            outcome: ProcessingOutcome.succeeded,
            createdAt: processed,
            latency: const Duration(milliseconds: 180),
          ),
          ProcessingRecord(
            memoryId: spec.id,
            capability: Capability.vision,
            provider: 'nvidia',
            model: 'nemotron-vl-3b',
            outcome: ProcessingOutcome.succeeded,
            createdAt: processed.subtract(const Duration(seconds: 4)),
            latency: const Duration(milliseconds: 3900),
          ),
        ],
        if (spec.status == ProcessingStatus.failed)
          ProcessingRecord(
            memoryId: spec.id,
            capability: Capability.vision,
            provider: 'nvidia',
            model: 'nemotron-vl-3b',
            outcome: ProcessingOutcome.failed,
            createdAt: added.add(const Duration(minutes: 40)),
            error: spec.failureReason,
          ),
      ];
    }
  }

  /// Rebuilds a memory with fields that `copyWith` can't clear.
  Memory rebuild(
    Memory m, {
    required ProcessingStatus status,
    String? failureReason,
    DateTime? processedAt,
  }) {
    return Memory(
      id: m.id,
      imagePath: m.imagePath,
      thumbnailPath: m.thumbnailPath,
      source: m.source,
      sha256: m.sha256,
      mimeType: m.mimeType,
      width: m.width,
      height: m.height,
      byteSize: m.byteSize,
      takenAt: m.takenAt,
      addedAt: m.addedAt,
      updatedAt: clock.now(),
      status: status,
      summary: m.summary,
      visualDescription: m.visualDescription,
      extractedText: m.extractedText,
      category: m.category,
      attempts: status == ProcessingStatus.captured ? 0 : m.attempts,
      failureReason: failureReason,
      processedAt: processedAt ?? m.processedAt,
      lastViewedAt: m.lastViewedAt,
    );
  }
}

class DemoMemoryStore implements MemoryStore {
  DemoMemoryStore(this.db);

  final DemoDatabase db;

  Iterable<Memory> get _live =>
      db.memories.values.where((m) => m.status != ProcessingStatus.deleted);

  @override
  Future<InsertOutcome> insertCaptured(
    List<NewMemory> memories,
    DateTime now,
  ) async {
    final inserted = <String>[];
    final duplicates = <NewMemory>[];
    for (final n in memories) {
      if (db.memories.values.any((m) => m.sha256 == n.sha256)) {
        duplicates.add(n);
        continue;
      }
      db.memories[n.id] = Memory(
        id: n.id,
        imagePath: n.imagePath,
        source: n.source,
        sha256: n.sha256,
        mimeType: n.mimeType,
        width: n.width,
        height: n.height,
        byteSize: n.byteSize,
        takenAt: n.takenAt,
        addedAt: now,
        updatedAt: now,
        status: ProcessingStatus.captured,
      );
      inserted.add(n.id);
    }
    if (inserted.isNotEmpty) db.touch();
    return InsertOutcome(insertedIds: inserted, duplicates: duplicates);
  }

  @override
  Future<Memory?> getMemory(String id) async => db.memories[id];

  @override
  Future<List<Memory>> getMemories(List<String> ids) async => [
    for (final id in ids) ?db.memories[id],
  ];

  @override
  Future<MemoryDetails?> getDetails(String id) async {
    final memory = db.memories[id];
    if (memory == null) return null;
    final cited = db.messages.values
        .where(
          (list) => list.any((m) => m.references.any((r) => r.memoryId == id)),
        )
        .length;
    return MemoryDetails(
      memory: memory,
      entities: db.entities[id] ?? const [],
      attributes: db.attributes[id] ?? const [],
      keywords: db.keywords[id] ?? const [],
      processing: [...?db.processing[id]]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      conversationCount: db.citationOverrides[id] ?? cited,
    );
  }

  @override
  Future<List<Memory>> listMemories(MemoryListQuery query) async {
    final list = _live.where((m) {
      if (query.categories.isNotEmpty &&
          !query.categories.contains(m.category)) {
        return false;
      }
      if (query.statuses.isNotEmpty && !query.statuses.contains(m.status)) {
        return false;
      }
      final range = query.takenBetween;
      if (range != null && !range.contains(m.takenAt)) return false;
      return true;
    }).toList();
    switch (query.sort) {
      case MemorySort.newest:
        list.sort((a, b) => b.takenAt.compareTo(a.takenAt));
      case MemorySort.oldest:
        list.sort((a, b) => a.takenAt.compareTo(b.takenAt));
      case MemorySort.category:
        list.sort((a, b) {
          final c = (a.category ?? '~').compareTo(b.category ?? '~');
          return c != 0 ? c : b.takenAt.compareTo(a.takenAt);
        });
      case MemorySort.recentlyViewed:
        list.sort(
          (a, b) => (b.lastViewedAt ?? DateTime(0)).compareTo(
            a.lastViewedAt ?? DateTime(0),
          ),
        );
    }
    return list.skip(query.offset).take(query.limit).toList();
  }

  @override
  Future<List<FacetCount>> categoryCounts() async {
    final counts = <String, int>{};
    for (final m in _live) {
      final category = m.category;
      if (category != null) counts[category] = (counts[category] ?? 0) + 1;
    }
    final list = [for (final e in counts.entries) FacetCount(e.key, e.value)]
      ..sort((a, b) => b.count.compareTo(a.count));
    return list;
  }

  @override
  Future<QueueSummary> queueSummary() async {
    var ready = 0, waiting = 0, processing = 0, failed = 0, total = 0;
    for (final m in _live) {
      total++;
      switch (m.status) {
        case ProcessingStatus.ready:
          ready++;
        case ProcessingStatus.captured || ProcessingStatus.reprocessing:
          waiting++;
        case ProcessingStatus.processing:
          processing++;
        case ProcessingStatus.failed:
          failed++;
        case ProcessingStatus.deleted:
          break;
      }
    }
    return QueueSummary(
      total: total,
      ready: ready,
      waiting: waiting,
      processing: processing,
      failed: failed,
    );
  }

  @override
  Future<StorageStats> storageStats() async => StorageStats(
    memoryCount: _live.length,
    imageBytes: _live.fold(0, (sum, m) => sum + m.byteSize),
  );

  @override
  Future<void> saveUnderstanding(
    String id,
    MemoryUnderstanding understanding,
    NormalizedFacts facts,
    DateTime now,
  ) async {
    final m = db.memories[id];
    if (m == null) return;
    db.memories[id] = m.copyWith(
      summary: understanding.summary,
      category: understanding.category,
      visualDescription: understanding.visualDescription,
      extractedText: understanding.extractedText,
      updatedAt: now,
    );
    db.entities[id] = facts.entities;
    db.attributes[id] = facts.attributes;
    db.keywords[id] = facts.keywords;
    db.touch();
  }

  @override
  Future<void> setThumbnail(
    String id,
    String thumbnailPath,
    DateTime now,
  ) async {
    final m = db.memories[id];
    if (m == null) return;
    db.memories[id] = m.copyWith(thumbnailPath: thumbnailPath, updatedAt: now);
    db.touch();
  }

  @override
  Future<void> markViewed(String id, DateTime now) async {
    final m = db.memories[id];
    if (m == null) return;
    db.memories[id] = m.copyWith(lastViewedAt: now);
  }

  @override
  Future<void> addProcessingRecord(ProcessingRecord record) async {
    (db.processing[record.memoryId] ??= []).add(record);
    db.touch();
  }

  @override
  Future<MemoryFiles?> deleteMemory(String id) async {
    final m = db.memories.remove(id);
    if (m == null) return null;
    db
      ..entities.remove(id)
      ..attributes.remove(id)
      ..keywords.remove(id)
      ..processing.remove(id)
      ..touch();
    return MemoryFiles(imagePath: m.imagePath, thumbnailPath: m.thumbnailPath);
  }

  @override
  Future<List<MemoryFiles>> deleteAll() async {
    final files = [
      for (final m in db.memories.values)
        MemoryFiles(imagePath: m.imagePath, thumbnailPath: m.thumbnailPath),
    ];
    db
      ..memories.clear()
      ..entities.clear()
      ..attributes.clear()
      ..keywords.clear()
      ..processing.clear()
      ..touch();
    return files;
  }

  @override
  Future<List<Memory>> missingThumbnails({int limit = 50}) async =>
      _live.where((m) => m.thumbnailPath == null).take(limit).toList();

  @override
  Future<int> dataVersion() async => db.version;
}

class DemoQueueStore implements QueueStore {
  DemoQueueStore(this.db);

  final DemoDatabase db;

  List<Memory> get _waiting =>
      db.memories.values
          .where(
            (m) =>
                m.status == ProcessingStatus.captured ||
                m.status == ProcessingStatus.reprocessing,
          )
          .toList()
        ..sort((a, b) => a.takenAt.compareTo(b.takenAt));

  @override
  Future<Memory?> claimNext(DateTime now, Duration lease) async {
    final waiting = _waiting;
    if (waiting.isEmpty) return null;
    final m = db.rebuild(waiting.first, status: ProcessingStatus.processing);
    db
      ..memories[m.id] = m
      ..touch();
    return m;
  }

  @override
  Future<void> markReady(String id, DateTime now) async {
    final m = db.memories[id];
    if (m == null) return;
    db
      ..memories[id] = db.rebuild(
        m,
        status: ProcessingStatus.ready,
        processedAt: now,
      )
      ..touch();
  }

  @override
  Future<void> releaseForRetry(
    String id, {
    required DateTime nextAttemptAt,
    required String reason,
    required DateTime now,
  }) async {
    final m = db.memories[id];
    if (m == null) return;
    db
      ..memories[id] = db.rebuild(m, status: ProcessingStatus.captured)
      ..touch();
  }

  @override
  Future<void> releaseWithoutAttempt(String id, DateTime now) =>
      releaseForRetry(id, nextAttemptAt: now, reason: '', now: now);

  @override
  Future<void> markFailed(String id, String reason, DateTime now) async {
    final m = db.memories[id];
    if (m == null) return;
    db
      ..memories[id] = db.rebuild(
        m,
        status: ProcessingStatus.failed,
        failureReason: reason,
      )
      ..touch();
  }

  @override
  Future<void> retry(String id, DateTime now) async {
    final m = db.memories[id];
    if (m == null || m.status != ProcessingStatus.failed) return;
    db
      ..memories[id] = db.rebuild(m, status: ProcessingStatus.captured)
      ..touch();
  }

  @override
  Future<void> requestReprocess(String id, DateTime now) async {
    final m = db.memories[id];
    if (m == null) return;
    db
      ..memories[id] = db.rebuild(m, status: ProcessingStatus.reprocessing)
      ..touch();
  }

  @override
  Future<List<QueueItem>> queueItems({
    int waitingLimit = 200,
    int recentLimit = 20,
  }) async {
    final all = db.memories.values;
    final processing =
        all.where((m) => m.status == ProcessingStatus.processing).toList()
          ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    final failed =
        all.where((m) => m.status == ProcessingStatus.failed).toList()
          ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    final done =
        all
            .where(
              (m) =>
                  m.status == ProcessingStatus.ready && m.processedAt != null,
            )
            .toList()
          ..sort((a, b) => b.processedAt!.compareTo(a.processedAt!));
    return [
      for (final m in processing) QueueItem(memory: m, position: null),
      for (final (i, m) in _waiting.take(waitingLimit).indexed)
        QueueItem(memory: m, position: i + 1),
      for (final m in failed) QueueItem(memory: m, position: null),
      for (final m in done.take(recentLimit))
        QueueItem(memory: m, position: null),
    ];
  }

  @override
  Future<bool> hasWork(DateTime now) async => _waiting.isNotEmpty;
}

class DemoConversationStore implements ConversationStore {
  DemoConversationStore(this.db);

  final DemoDatabase db;

  @override
  Future<Conversation> createConversation(
    String id,
    String title,
    DateTime now,
  ) async {
    final c = Conversation(
      id: id,
      title: title,
      createdAt: now,
      updatedAt: now,
    );
    db.conversations[id] = c;
    db.messages[id] = [];
    db.touch();
    return c;
  }

  @override
  Future<List<Conversation>> listConversations() async =>
      db.conversations.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<Conversation?> getConversation(String id) async =>
      db.conversations[id];

  @override
  Future<List<ChatMessage>> messages(String conversationId) async => [
    ...?db.messages[conversationId],
  ];

  @override
  Future<void> addMessage(ChatMessage message) async {
    (db.messages[message.conversationId] ??= []).add(message);
    final c = db.conversations[message.conversationId];
    if (c != null) {
      db.conversations[c.id] = Conversation(
        id: c.id,
        title: c.title,
        createdAt: c.createdAt,
        updatedAt: message.createdAt,
      );
    }
    db.touch();
  }

  @override
  Future<void> saveResultSet(ResultSet resultSet) async =>
      db.resultSets.add(resultSet);

  @override
  Future<ResultSet?> latestResultSet(String conversationId) async =>
      db.resultSets.where((r) => r.conversationId == conversationId).lastOrNull;

  @override
  Future<ResultSet?> getResultSet(String id) async =>
      db.resultSets.where((r) => r.id == id).firstOrNull;

  @override
  Future<int> conversationsCiting(String memoryId) async => db.messages.values
      .where(
        (list) =>
            list.any((m) => m.references.any((r) => r.memoryId == memoryId)),
      )
      .length;

  @override
  Future<void> deleteConversation(String id) async {
    db
      ..conversations.remove(id)
      ..messages.remove(id)
      ..touch();
  }
}

class DemoSettingsStore implements SettingsStore {
  final Map<String, Object?> values = {};

  @override
  Future<Object?> read(String key) async => values[key];

  @override
  Future<void> write(String key, Object? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

class DemoSecretStore implements SecretStore {
  final Map<String, String> values = {};

  /// When set, the next write or delete throws.
  bool failNext = false;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<List<String>> keys() async => values.keys.toList();

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failNext) {
      failNext = false;
      throw StateError('The keystore is unavailable');
    }
    values[key] = value;
  }
}

class DemoImageFiles implements ImageFiles {
  DemoImageFiles(this.db, this.renderer);

  final DemoDatabase db;
  final DemoImageRenderer renderer;

  @override
  Future<Uint8List> readBytes(String relativePath) {
    final image = db.images[relativePath];
    if (image == null) return Future.value(Uint8List(0));
    return renderer.render(image.$1, seed: image.$2);
  }

  @override
  Future<String> createThumbnail(String sourcePath, {int maxEdge = 512}) async {
    final name = sourcePath.split('/').last.split('.').first;
    final path = 'thumbnails/$name.webp';
    final source = db.images[sourcePath];
    if (source != null) db.images[path] = source;
    return path;
  }

  @override
  Future<void> delete(List<String> relativePaths) async {
    relativePaths.forEach(db.images.remove);
  }

  @override
  String absolutePath(String relativePath) => '/demo/files/$relativePath';
}
