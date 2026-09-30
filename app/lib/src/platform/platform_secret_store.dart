import 'package:memora_core/memora_core.dart';

import 'messages.g.dart';

/// [SecretStore] backed by the Android Keystore through [SecretHostApi].
///
/// Values are encrypted on the Kotlin side before they are written to disk.
/// Nothing here logs or caches a value.
class PlatformSecretStore implements SecretStore {
  PlatformSecretStore({SecretHostApi? host}) : _host = host ?? SecretHostApi();

  final SecretHostApi _host;

  @override
  Future<String?> read(String key) => _host.read(key);

  @override
  Future<void> write(String key, String value) => _host.write(key, value);

  @override
  Future<void> delete(String key) => _host.delete(key);

  @override
  Future<List<String>> keys() => _host.keys();
}
