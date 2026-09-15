import 'dart:typed_data';

import 'package:memora/src/services/app_services.dart';
import 'package:memora_core/memora_core.dart';

class IngestCall {
  IngestCall(this.files, this.source);

  final List<ImportedFile> files;
  final MemorySource source;
}

class FakeIngestor implements MemoryIngestor {
  FakeIngestor({this.duplicatesPerBatch = 0, this.fail = false});

  final int duplicatesPerBatch;
  final bool fail;
  final calls = <IngestCall>[];

  @override
  Future<IngestReport> ingest(
    List<ImportedFile> files,
    MemorySource source,
  ) async {
    if (fail) throw StateError('database is locked');
    calls.add(IngestCall(files, source));
    final added = files.length - duplicatesPerBatch;
    return IngestReport(
      addedIds: [for (var i = 0; i < added; i++) 'id$i'],
      duplicateCount: duplicatesPerBatch,
    );
  }

  @override
  Future<int> backfillThumbnails() async => 0;
}

class FakeScheduler implements QueueScheduler {
  var refreshes = 0;

  @override
  Future<QueuePolicy> policy() async => const QueuePolicy();

  @override
  Future<void> processNow() async {}

  @override
  Future<void> refresh() async => refreshes++;

  @override
  Future<void> setPolicy(QueuePolicy policy) async {}
}

class FakeImageFiles implements ImageFiles {
  final deleted = <String>[];

  @override
  String absolutePath(String relativePath) => '/files/$relativePath';

  @override
  Future<String> createThumbnail(String sourcePath, {int maxEdge = 512}) =>
      throw UnimplementedError();

  @override
  Future<void> delete(List<String> relativePaths) async =>
      deleted.addAll(relativePaths);

  @override
  Future<Uint8List> readBytes(String relativePath) =>
      throw UnimplementedError();
}

class MemorySettings implements SettingsStore {
  final _values = <String, Object?>{};

  @override
  Future<Object?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, Object? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}

class NoSecrets implements SecretStore {
  @override
  Future<void> delete(String key) async {}

  @override
  Future<List<String>> keys() async => const [];

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}

class FixedClock implements Clock {
  const FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}
