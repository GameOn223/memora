import 'package:memora_core/memora_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'codec.dart';

/// Status values that are waiting to be claimed.
const waitingStatuses = "('captured', 'reprocessing')";

/// Maps a `SELECT * FROM memories` row.
Memory memoryFromRow(Row row) {
  return Memory(
    id: row['id'] as String,
    imagePath: row['image_path'] as String,
    thumbnailPath: row['thumbnail_path'] as String?,
    source: MemorySource.fromDb(row['source'] as String),
    sha256: row['sha256'] as String,
    mimeType: row['mime_type'] as String,
    width: row['width'] as int,
    height: row['height'] as int,
    byteSize: row['byte_size'] as int,
    takenAt: fromMillis(row['taken_at'] as int),
    addedAt: fromMillis(row['added_at'] as int),
    updatedAt: fromMillis(row['updated_at'] as int),
    status: ProcessingStatus.fromDb(row['status'] as String),
    summary: row['summary'] as String?,
    visualDescription: row['visual_description'] as String?,
    extractedText: row['extracted_text'] as String?,
    category: row['category'] as String?,
    attempts: row['attempts'] as int,
    failureReason: row['failure_reason'] as String?,
    processedAt: fromMillisOrNull(row['processed_at']),
    lastViewedAt: fromMillisOrNull(row['last_viewed_at']),
  );
}

/// Maps an `attributes` row.
StoredAttribute attributeFromRow(Row row) {
  return StoredAttribute(
    type: row['type'] as String,
    value: row['value'] as String,
    valueNum: (row['value_num'] as num?)?.toDouble(),
    valueDate: row['value_date'] as String?,
    currency: row['currency'] as String?,
    label: row['label'] as String?,
  );
}
