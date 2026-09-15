import 'dart:io';

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
