import 'dart:convert';

import 'package:memora_core/memora_core.dart';
import 'package:memora_database/memora_database.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  late MemoraDatabase db;
  late SettingsStore settings;

  setUp(() {
    db = openTestDatabase();
    settings = db.settings;
  });

  test('reads back JSON values of every kind', () async {
    final values = <String, Object?>{
      'queue_policy': {
        'mode': 'overnight',
        'paused': false,
        'window_start_minutes': 60,
        'nested': {
          'list': [1, 'two', null],
        },
      },
      'recent_searches': ['bills', 'flights'],
      'local_only': true,
      'density': 4,
      'text_scale': 1.15,
      'theme': 'dark',
    };
    for (final MapEntry(:key, :value) in values.entries) {
      await settings.write(key, value);
    }
    for (final MapEntry(:key, :value) in values.entries) {
      expect(await settings.read(key), value, reason: key);
    }
  });

  test('overwrites an existing key', () async {
    await settings.write('theme', 'dark');
    await settings.write('theme', 'light');
    expect(await settings.read('theme'), 'light');
    expect(scalar(db, 'SELECT COUNT(*) FROM settings'), 1);
  });

  test('returns null for a missing key', () async {
    expect(await settings.read('nothing'), isNull);
  });

  test('writing null deletes the key', () async {
    await settings.write('theme', 'dark');
    await settings.write('theme', null);
    expect(await settings.read('theme'), isNull);
    expect(scalar(db, 'SELECT COUNT(*) FROM settings'), 0);

    await settings.write('never_set', null);
    expect(scalar(db, 'SELECT COUNT(*) FROM settings'), 0);
  });

  test('refuses values that are not JSON and keeps the old one', () async {
    await settings.write('when', 'yesterday');
    await expectLater(
      () => settings.write('when', DateTime.utc(2026)),
      throwsA(isA<JsonUnsupportedObjectError>()),
    );
    expect(await settings.read('when'), 'yesterday');
  });

  test('survives reopening a file database', () async {
    final path = tempDatabasePath();
    final first = MemoraDatabase.open(path);
    await first.settings.write('queue_policy', {'mode': 'immediate'});
    first.close();

    final second = MemoraDatabase.open(path);
    addTearDown(second.close);
    expect(await second.settings.read('queue_policy'), {'mode': 'immediate'});
  });
}
