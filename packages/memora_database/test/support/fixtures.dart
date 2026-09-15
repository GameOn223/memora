import 'dart:io';

import 'package:memora_core/memora_core.dart';
import 'package:memora_database/memora_database.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Returns a path for a database file inside a fresh temporary directory. The
/// directory is removed after the test. Close every connection to the file in
/// a teardown registered after calling this, so it runs first.
String tempDatabasePath() {
  final dir = Directory.systemTemp.createTempSync('memora_db_test_');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows can hold on to WAL files for a moment. Leftovers are harmless.
    }
  });
  return p.join(dir.path, 'memora.db');
}

/// Opens an in-memory database that is closed after the test.
MemoraDatabase openTestDatabase() {
  final db = MemoraDatabase.openInMemory();
  addTearDown(db.close);
  return db;
}

var _sequence = 0;

/// A new memory with unique id and hash unless given.
NewMemory newMemory({
  String? id,
  String? sha256,
  DateTime? takenAt,
  MemorySource source = MemorySource.gallery,
  String mimeType = 'image/png',
  int width = 1080,
  int height = 2400,
  int byteSize = 1000,
}) {
  final n = ++_sequence;
  final memoryId = id ?? 'memory-$n';
  return NewMemory(
    id: memoryId,
    imagePath: 'originals/$memoryId.png',
    source: source,
    sha256: sha256 ?? 'sha-$memoryId-$n',
    mimeType: mimeType,
    width: width,
    height: height,
    byteSize: byteSize,
    takenAt: takenAt ?? DateTime.utc(2026, 9, 1).add(Duration(minutes: n)),
  );
}

/// Inserts one captured memory and returns its id.
Future<String> seedMemory(
  MemoraDatabase db, {
  String? id,
  DateTime? takenAt,
  DateTime? now,
  int byteSize = 1000,
}) async {
  final memory = newMemory(id: id, takenAt: takenAt, byteSize: byteSize);
  final outcome = await db.memories.insertCaptured([
    memory,
  ], now ?? DateTime.utc(2026, 9, 15));
  return outcome.insertedIds.single;
}

/// Forces a status and queue columns with raw SQL, for arranging tests.
void setStatus(
  MemoraDatabase db,
  String id,
  ProcessingStatus status, {
  int? attempts,
  DateTime? leaseUntil,
  DateTime? nextAttemptAt,
  DateTime? processedAt,
}) {
  db.connection.execute(
    'UPDATE memories SET status = ?, attempts = COALESCE(?, attempts), '
    'lease_until = ?, next_attempt_at = ?, '
    'processed_at = COALESCE(?, processed_at) WHERE id = ?',
    [
      status.dbValue,
      attempts,
      leaseUntil?.millisecondsSinceEpoch,
      nextAttemptAt?.millisecondsSinceEpoch,
      processedAt?.millisecondsSinceEpoch,
      id,
    ],
  );
}

MemoryUnderstanding understanding({
  String summary = 'Reliance electricity bill for August 2026',
  String category = 'utility_bill',
  String visualDescription = 'A utility bill displayed in a mobile app.',
  String extractedText = 'Reliance Energy. Amount due Rs 1,842. Due 31/08/2026',
  List<String> keywords = const ['reliance', 'electricity', 'bill'],
}) {
  return MemoryUnderstanding(
    summary: summary,
    category: category,
    visualDescription: visualDescription,
    extractedText: extractedText,
    keywords: keywords,
  );
}

NormalizedFacts facts({
  List<StoredEntity> entities = const [],
  List<StoredAttribute> attributes = const [],
  List<String> keywords = const [],
}) {
  return NormalizedFacts(
    entities: entities,
    attributes: attributes,
    keywords: keywords,
  );
}

StoredEntity entity(String type, String value) => StoredEntity(
  type: type,
  value: value,
  normalizedValue: value.trim().toLowerCase(),
);

StoredAttribute amount(double value, {String currency = 'INR', String? label}) {
  return StoredAttribute(
    type: 'amount',
    value: '$currency ${value.toStringAsFixed(0)}',
    valueNum: value,
    currency: currency,
    label: label,
  );
}

StoredAttribute dateAttribute(String type, String isoDate) =>
    StoredAttribute(type: type, value: isoDate, valueDate: isoDate);

StoredAttribute textAttribute(String type, String value) =>
    StoredAttribute(type: type, value: value);

/// Runs a scalar query and returns the first column of the first row.
Object? scalar(MemoraDatabase db, String sql, [List<Object?> args = const []]) {
  return db.connection.select(sql, args).first.columnAt(0) as Object?;
}
