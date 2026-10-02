import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

/// A mutable memory row. [Memory.copyWith] can't clear fields, so the fakes
/// keep their own rows and hand out immutable [Memory] values.
class MemoryRow {
  MemoryRow({
    required this.seq,
    required this.id,
    required this.imagePath,
    required this.source,
    required this.sha256,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.byteSize,
    required this.takenAt,
    required this.addedAt,
    required this.updatedAt,
    required this.status,
  });

  final int seq;
  final String id;
  String imagePath;
  String? thumbnailPath;
  MemorySource source;
  String sha256;
  String mimeType;
  int width;
  int height;
  int byteSize;
  DateTime takenAt;
  DateTime addedAt;
  DateTime updatedAt;
  ProcessingStatus status;
  String? summary;
  String? visualDescription;
  String? extractedText;
  String? category;
  int attempts = 0;
  DateTime? leaseUntil;
  DateTime? nextAttemptAt;
  String? failureReason;
  DateTime? processedAt;
  DateTime? lastViewedAt;
  List<StoredEntity> entities = [];
  List<StoredAttribute> attributes = [];
  List<String> keywords = [];
  final List<ProcessingRecord> processing = [];

  /// Vectors keyed by [vectorKey].
  final Map<String, ({Float32List vector, EmbeddingModelInfo model})> vectors =
      {};

  Memory toMemory() => Memory(
    id: id,
    imagePath: imagePath,
    thumbnailPath: thumbnailPath,
    source: source,
    sha256: sha256,
    mimeType: mimeType,
    width: width,
    height: height,
    byteSize: byteSize,
    takenAt: takenAt,
    addedAt: addedAt,
    updatedAt: updatedAt,
    status: status,
    summary: summary,
    visualDescription: visualDescription,
    extractedText: extractedText,
    category: category,
    attempts: attempts,
    failureReason: failureReason,
    processedAt: processedAt,
    lastViewedAt: lastViewedAt,
  );
}

String vectorKey(EmbeddingModelInfo model) =>
    '${model.storageId}@${model.version}#${model.dimensions}';

/// Shared state behind every fake store, so a memory written through one port
/// is visible through the others, as with the real database.
abstract class FakeMemoraState {
  final Map<String, MemoryRow> rows = {};
  final Map<String, Conversation> conversationRows = {};
  final List<ChatMessage> messageRows = [];
  final List<ResultSet> resultSetRows = [];

  int _seq = 0;
  int version = 0;

  int nextSeq() => ++_seq;

  void touch() => version++;

  Iterable<MemoryRow> get liveRows =>
      rows.values.where((r) => r.status != ProcessingStatus.deleted);

  /// Adds a memory directly, for arranging tests. Everything not given gets a
  /// plausible default.
  Memory seed({
    required String id,
    DateTime? takenAt,
    DateTime? addedAt,
    ProcessingStatus status = ProcessingStatus.ready,
    String? summary,
    String? category,
    String? visualDescription,
    String? extractedText,
    String? imagePath,
    String? thumbnailPath,
    String mimeType = 'image/png',
    int byteSize = 1000,
    List<StoredEntity> entities = const [],
    List<StoredAttribute> attributes = const [],
    List<String> keywords = const [],
    int attempts = 0,
    DateTime? processedAt,
  }) {
    final taken = takenAt ?? DateTime(2026, 9, 1);
    final row =
        MemoryRow(
            seq: nextSeq(),
            id: id,
            imagePath: imagePath ?? 'originals/$id.png',
            source: MemorySource.gallery,
            sha256: 'sha-$id',
            mimeType: mimeType,
            width: 1080,
            height: 2400,
            byteSize: byteSize,
            takenAt: taken,
            addedAt: addedAt ?? taken,
            updatedAt: addedAt ?? taken,
            status: status,
          )
          ..thumbnailPath = thumbnailPath
          ..summary = summary
          ..category = category
          ..visualDescription = visualDescription
          ..extractedText = extractedText
          ..entities = [...entities]
          ..attributes = [...attributes]
          ..keywords = [...keywords]
          ..attempts = attempts
          ..processedAt = processedAt;
    rows[id] = row;
    touch();
    return row.toMemory();
  }
}
