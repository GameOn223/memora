import 'package:meta/meta.dart';

/// Where a memory sits in its lifecycle. See docs/architecture.md, section 5.1.
enum ProcessingStatus {
  captured('captured'),
  processing('processing'),
  ready('ready'),
  failed('failed'),
  reprocessing('reprocessing'),
  deleted('deleted');

  const ProcessingStatus(this.dbValue);

  /// The lowercase value stored in the `memories.status` column.
  final String dbValue;

  static ProcessingStatus fromDb(String value) =>
      ProcessingStatus.values.firstWhere(
        (s) => s.dbValue == value,
        orElse: () =>
            throw ArgumentError.value(value, 'value', 'Unknown status'),
      );

  /// True while the memory is waiting for, or going through, understanding.
  bool get isPending =>
      this == captured || this == processing || this == reprocessing;
}

/// How an image got into Memora.
enum MemorySource {
  gallery('gallery'),
  tile('tile'),
  share('share');

  const MemorySource(this.dbValue);

  final String dbValue;

  static MemorySource fromDb(String value) => MemorySource.values.firstWhere(
    (s) => s.dbValue == value,
    orElse: () => throw ArgumentError.value(value, 'value', 'Unknown source'),
  );
}

/// One saved image and whatever Memora has understood about it so far.
///
/// Paths are relative to the app's files directory so the database stays
/// valid if Android moves app storage.
@immutable
class Memory {
  const Memory({
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
    this.thumbnailPath,
    this.summary,
    this.visualDescription,
    this.extractedText,
    this.category,
    this.attempts = 0,
    this.failureReason,
    this.processedAt,
    this.lastViewedAt,
  });

  final String id;
  final String imagePath;
  final String? thumbnailPath;
  final MemorySource source;
  final String sha256;
  final String mimeType;
  final int width;
  final int height;
  final int byteSize;

  /// When the image was taken. Memories are filed under this date.
  final DateTime takenAt;

  /// When the image was added to Memora.
  final DateTime addedAt;
  final DateTime updatedAt;
  final ProcessingStatus status;
  final String? summary;
  final String? visualDescription;
  final String? extractedText;
  final String? category;
  final int attempts;
  final String? failureReason;
  final DateTime? processedAt;
  final DateTime? lastViewedAt;

  /// True when the image was added on a later calendar day than it was taken.
  /// The grid shows a small history glyph for these.
  bool get addedLater {
    final taken = takenAt.toLocal();
    final added = addedAt.toLocal();
    return DateTime(
      added.year,
      added.month,
      added.day,
    ).isAfter(DateTime(taken.year, taken.month, taken.day));
  }

  Memory copyWith({
    String? thumbnailPath,
    ProcessingStatus? status,
    String? summary,
    String? visualDescription,
    String? extractedText,
    String? category,
    int? attempts,
    String? failureReason,
    DateTime? updatedAt,
    DateTime? processedAt,
    DateTime? lastViewedAt,
  }) {
    return Memory(
      id: id,
      imagePath: imagePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      source: source,
      sha256: sha256,
      mimeType: mimeType,
      width: width,
      height: height,
      byteSize: byteSize,
      takenAt: takenAt,
      addedAt: addedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      summary: summary ?? this.summary,
      visualDescription: visualDescription ?? this.visualDescription,
      extractedText: extractedText ?? this.extractedText,
      category: category ?? this.category,
      attempts: attempts ?? this.attempts,
      failureReason: failureReason ?? this.failureReason,
      processedAt: processedAt ?? this.processedAt,
      lastViewedAt: lastViewedAt ?? this.lastViewedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Memory &&
      other.id == id &&
      other.updatedAt == updatedAt &&
      other.status == status &&
      other.thumbnailPath == thumbnailPath;

  @override
  int get hashCode => Object.hash(id, updatedAt, status, thumbnailPath);

  @override
  String toString() => 'Memory($id, ${status.dbValue}, $category)';
}

/// A file that has been copied into app storage and is ready to become a
/// memory row.
@immutable
class NewMemory {
  const NewMemory({
    required this.id,
    required this.imagePath,
    required this.source,
    required this.sha256,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.byteSize,
    required this.takenAt,
  });

  final String id;
  final String imagePath;
  final MemorySource source;
  final String sha256;
  final String mimeType;
  final int width;
  final int height;
  final int byteSize;
  final DateTime takenAt;
}

/// What happened when a batch of new memories was inserted.
@immutable
class InsertOutcome {
  const InsertOutcome({required this.insertedIds, required this.duplicates});

  /// Ids of rows that were created, in input order.
  final List<String> insertedIds;

  /// Inputs skipped because an image with the same SHA-256 already exists.
  /// Their files should be removed by the caller.
  final List<NewMemory> duplicates;
}

/// Files that belonged to a deleted memory and should be removed from disk.
@immutable
class MemoryFiles {
  const MemoryFiles({required this.imagePath, this.thumbnailPath});

  final String imagePath;
  final String? thumbnailPath;

  List<String> get all => [imagePath, ?thumbnailPath];
}
