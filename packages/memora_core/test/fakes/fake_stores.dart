import 'package:memora_core/memora_core.dart';

export 'fake_ai.dart';
export 'fake_image_files.dart';
export 'fake_memora.dart';

class InMemorySettingsStore implements SettingsStore {
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

class InMemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<List<String>> keys() async => values.keys.toList();

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class FixedClock implements Clock {
  FixedClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;

  void advance(Duration d) => current = current.add(d);
}

class SequentialIds implements IdGenerator {
  int _next = 1;

  @override
  String next() => 'id-${_next++}';
}
