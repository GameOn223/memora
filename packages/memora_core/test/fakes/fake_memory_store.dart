import 'dart:math' as math;

import 'package:memora_core/memora_core.dart';

import 'fake_memora_state.dart';

/// In-memory [MemoryStore] following the port docs.
mixin FakeMemoryStore on FakeMemoraState implements MemoryStore {
  @override
  Future<InsertOutcome> insertCaptured(
    List<NewMemory> memories,
    DateTime now,
  ) async {
    final inserted = <String>[];
    final duplicates = <NewMemory>[];
    final shas = {for (final r in rows.values) r.sha256};
    for (final m in memories) {
      if (!shas.add(m.sha256)) {
        duplicates.add(m);
        continue;
      }
      rows[m.id] = MemoryRow(
        seq: nextSeq(),
        id: m.id,
        imagePath: m.imagePath,
        source: m.source,
        sha256: m.sha256,
        mimeType: m.mimeType,
        width: m.width,
        height: m.height,
        byteSize: m.byteSize,
        takenAt: m.takenAt,
        addedAt: now,
        updatedAt: now,
        status: ProcessingStatus.captured,
      );
      inserted.add(m.id);
    }
    touch();
    return InsertOutcome(insertedIds: inserted, duplicates: duplicates);
  }

  @override
  Future<Memory?> getMemory(String id) async => rows[id]?.toMemory();

  @override
  Future<List<Memory>> getMemories(List<String> ids) async => [
    for (final id in ids)
      if (rows[id] case final row?) row.toMemory(),
  ];

  @override
  Future<MemoryDetails?> getDetails(String id) async {
    final row = rows[id];
    if (row == null) return null;
    final conversations = {
      for (final m in messageRows)
        if (m.references.any((r) => r.memoryId == id)) m.conversationId,
    };
    final processing = [...row.processing]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return MemoryDetails(
      memory: row.toMemory(),
      entities: [...row.entities],
      attributes: [...row.attributes],
      keywords: [...row.keywords],
      processing: processing,
      conversationCount: conversations.length,
    );
  }

  @override
  Future<List<Memory>> listMemories(MemoryListQuery query) async {
    final filtered = liveRows.where((r) {
      if (query.categories.isNotEmpty &&
          !query.categories.contains(r.category)) {
        return false;
      }
      if (query.statuses.isNotEmpty && !query.statuses.contains(r.status)) {
        return false;
      }
      final range = query.takenBetween;
      return range == null || range.contains(r.takenAt);
    }).toList();
    int byTakenDesc(MemoryRow a, MemoryRow b) => b.takenAt.compareTo(a.takenAt);
    filtered.sort(switch (query.sort) {
      MemorySort.newest => byTakenDesc,
      MemorySort.oldest => (a, b) => a.takenAt.compareTo(b.takenAt),
      MemorySort.category => (a, b) {
        if (a.category == b.category) return byTakenDesc(a, b);
        if (a.category == null) return 1;
        if (b.category == null) return -1;
        return a.category!.compareTo(b.category!);
      },
      MemorySort.recentlyViewed => (a, b) {
        if (a.lastViewedAt == b.lastViewedAt) return 0;
        if (a.lastViewedAt == null) return 1;
        if (b.lastViewedAt == null) return -1;
        return b.lastViewedAt!.compareTo(a.lastViewedAt!);
      },
    });
    return filtered
        .skip(query.offset)
        .take(query.limit)
        .map((r) => r.toMemory())
        .toList();
  }

  @override
  Future<List<FacetCount>> categoryCounts() async {
    final counts = <String, int>{};
    for (final r in liveRows) {
      if (r.category case final c?) counts[c] = (counts[c] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return [for (final e in entries) FacetCount(e.key, e.value)];
  }

  @override
  Future<QueueSummary> queueSummary() async {
    int count(Set<ProcessingStatus> s) =>
        liveRows.where((r) => s.contains(r.status)).length;
    return QueueSummary(
      total: liveRows.length,
      ready: count({ProcessingStatus.ready}),
      waiting: count({
        ProcessingStatus.captured,
        ProcessingStatus.reprocessing,
      }),
      processing: count({ProcessingStatus.processing}),
      failed: count({ProcessingStatus.failed}),
    );
  }

  @override
  Future<StorageStats> storageStats() async => StorageStats(
    memoryCount: liveRows.length,
    imageBytes: liveRows.fold(0, (sum, r) => sum + r.byteSize),
  );

  @override
  Future<void> saveUnderstanding(
    String id,
    MemoryUnderstanding understanding,
    NormalizedFacts facts,
    DateTime now,
  ) async {
    final row = rows[id];
    if (row == null) return;
    row
      ..summary = understanding.summary
      ..visualDescription = understanding.visualDescription
      ..extractedText = understanding.extractedText
      ..category = understanding.category
      ..entities = [...facts.entities]
      ..attributes = [...facts.attributes]
      ..keywords = [...facts.keywords]
      ..updatedAt = now;
    touch();
  }

  @override
  Future<void> setThumbnail(
    String id,
    String thumbnailPath,
    DateTime now,
  ) async {
    rows[id]
      ?..thumbnailPath = thumbnailPath
      ..updatedAt = now;
    touch();
  }

  @override
  Future<void> markViewed(String id, DateTime now) async {
    rows[id]?.lastViewedAt = now;
    touch();
  }

  @override
  Future<void> addProcessingRecord(ProcessingRecord record) async {
    if (failProcessingRecords) throw StateError('database is locked');
    rows[record.memoryId]?.processing.add(record);
    touch();
  }

  @override
  Future<MemoryFiles?> deleteMemory(String id) async {
    final row = rows.remove(id);
    if (row == null) return null;
    _dropReferences({id});
    touch();
    return MemoryFiles(
      imagePath: row.imagePath,
      thumbnailPath: row.thumbnailPath,
    );
  }

  @override
  Future<List<MemoryFiles>> deleteAll() async {
    final files = [
      for (final r in rows.values)
        MemoryFiles(imagePath: r.imagePath, thumbnailPath: r.thumbnailPath),
    ];
    _dropReferences(rows.keys.toSet());
    rows.clear();
    touch();
    return files;
  }

  void _dropReferences(Set<String> ids) {
    for (var i = 0; i < messageRows.length; i++) {
      final m = messageRows[i];
      if (!m.references.any((r) => ids.contains(r.memoryId))) continue;
      messageRows[i] = ChatMessage(
        id: m.id,
        conversationId: m.conversationId,
        role: m.role,
        content: m.content,
        createdAt: m.createdAt,
        references: [
          for (final r in m.references)
            if (!ids.contains(r.memoryId)) r,
        ],
        toolTrace: m.toolTrace,
        presentation: m.presentation,
        provider: m.provider,
        model: m.model,
      );
    }
  }

  @override
  Future<List<Memory>> missingThumbnails({int limit = 50}) async {
    final missing = liveRows.where((r) => r.thumbnailPath == null).toList()
      ..sort((a, b) {
        final byAdded = a.addedAt.compareTo(b.addedAt);
        return byAdded != 0 ? byAdded : a.seq.compareTo(b.seq);
      });
    return [for (final r in missing.take(math.max(0, limit))) r.toMemory()];
  }

  @override
  Future<int> dataVersion() async => version;
}
