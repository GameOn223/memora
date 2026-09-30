import 'dart:convert';

import 'package:memora_core/memora_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'codec.dart';

/// [SettingsStore] on SQLite. Each value is stored as JSON text.
///
/// Never put secrets here. API keys belong in the platform [SecretStore].
class SqliteSettingsStore implements SettingsStore {
  SqliteSettingsStore(this._db);

  final Database _db;

  @override
  Future<Object?> read(String key) async {
    final rows = _db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return rows.isEmpty ? null : decodeJson(rows.first['value'] as String);
  }

  /// Writing null removes the key. Throws a [JsonUnsupportedObjectError] for
  /// values that can't be encoded as JSON, leaving any stored value as it was.
  @override
  Future<void> write(String key, Object? value) async {
    if (value == null) {
      _db.execute('DELETE FROM settings WHERE key = ?', [key]);
      return;
    }
    final encoded = jsonEncode(value);
    _db.execute(
      'INSERT INTO settings (key, value) VALUES (?, ?) '
      'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
      [key, encoded],
    );
  }
}
