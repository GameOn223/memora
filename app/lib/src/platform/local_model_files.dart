import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:memora_core/memora_core.dart';
import 'package:memora_providers/memora_providers.dart';

import '../services/app_services.dart';

/// Raised when a downloaded file doesn't match its pinned size or hash. The
/// partial file is already deleted when this is thrown.
class ModelVerificationException implements Exception {
  const ModelVerificationException(this.message);

  final String message;

  @override
  String toString() => 'ModelVerificationException: $message';
}

/// Raised when the server doesn't return the file.
class ModelDownloadException implements Exception {
  const ModelDownloadException(this.message);

  final String message;

  @override
  String toString() => 'ModelDownloadException: $message';
}

/// The header git hashes before a blob's bytes: `blob <size>` and a zero
/// byte. Written as a code unit so no escape can go missing.
List<int> gitBlobHeader(int size) => [...utf8.encode('blob $size'), 0];

/// Git's object id for a blob: SHA-1 over the header plus the bytes.
String gitBlobSha1(List<int> bytes) {
  final sink = _DigestSink._(null);
  sha1.startChunkedConversion(sink)
    ..add(gitBlobHeader(bytes.length))
    ..add(bytes)
    ..close();
  return sink.value.toString();
}

/// On-device model files under `files/models/<model id>/`.
///
/// A file only gets its final name after its size and hash check out, so a
/// file that exists with the right size is a verified file. That is how
/// state survives restarts without a separate record.
class PlatformLocalModelFiles implements LocalModelFiles {
  PlatformLocalModelFiles({
    required this.modelsDir,
    this.catalog = localModelCatalog,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// How long [remove] waits for a running download to notice.
  static const cancelTimeout = Duration(seconds: 10);

  /// Absolute path of `files/models`.
  final String modelsDir;
  final List<LocalModelSpec> catalog;
  final http.Client _client;

  final _jobs = <String, _DownloadJob>{};
  final _failed = <String>{};
  final _changes = StreamController<void>.broadcast(sync: true);

  /// Fires whenever a state or progress value changes.
  Stream<void> get changes => _changes.stream;

  LocalModelSpec spec(String modelId) => catalog.firstWhere(
    (s) => s.id == modelId,
    orElse: () =>
        throw ArgumentError.value(modelId, 'modelId', 'Unknown local model'),
  );

  /// Download progress from 0 to 1, or null when nothing is downloading.
  double? progress(String modelId) => _jobs[modelId]?.progress;

  @override
  Future<LocalModelState> state(String modelId) async {
    final model = spec(modelId);
    if (_jobs.containsKey(modelId)) return LocalModelState.downloading;
    if (await _allPresent(model)) return LocalModelState.ready;
    if (_failed.contains(modelId)) return LocalModelState.failed;
    return LocalModelState.notDownloaded;
  }

  @override
  Future<String?> path(String modelId, String fileName) async {
    final model = spec(modelId);
    for (final file in model.files) {
      if (file.name != fileName) continue;
      final target = File(_filePath(model, file));
      return await _isComplete(target, file) ? target.path : null;
    }
    return null;
  }

  @override
  Stream<double> download(String modelId) {
    final model = spec(modelId);
    final running = _jobs[modelId];
    if (running != null) return running.progressStream;
    final job = _DownloadJob();
    _jobs[modelId] = job;
    _failed.remove(modelId);
    _notify();
    // Starts after the caller has had a chance to listen.
    scheduleMicrotask(() => _run(model, job));
    return job.progressStream;
  }

  @override
  Future<void> remove(String modelId) async {
    final model = spec(modelId);
    final job = _jobs[modelId];
    if (job != null) {
      job.cancelled = true;
      // A stalled socket shouldn't block the settings screen forever. The
      // download writes to a `.part` file, which the delete below removes.
      await job.done.future.timeout(cancelTimeout, onTimeout: () {});
    }
    final dir = Directory(_modelDir(model));
    if (await dir.exists()) await dir.delete(recursive: true);
    _failed.remove(modelId);
    _notify();
  }

  /// Releases the HTTP client. Only needed in tests.
  Future<void> close() async {
    _client.close();
    await _changes.close();
  }

  Future<void> _run(LocalModelSpec model, _DownloadJob job) async {
    final total = model.totalBytes;
    var finishedBytes = 0;
    try {
      await Directory(_modelDir(model)).create(recursive: true);
      for (final file in model.files) {
        final target = File(_filePath(model, file));
        if (!await _isComplete(target, file)) {
          await _downloadFile(file, target, job, (received) {
            job.report((finishedBytes + received) / total, _notify);
          });
        }
        finishedBytes += file.size;
        job.report(finishedBytes / total, _notify);
      }
      // report() already emits exactly 1 when the last file lands.
      if (job.progress < 1) job.controller.add(1);
    } on _Cancelled {
      // remove() asked for this; it deletes the directory next.
    } catch (error, stack) {
      _failed.add(model.id);
      job.controller.addError(error, stack);
    } finally {
      _jobs.remove(model.id);
      _notify();
      await job.controller.close();
      job.done.complete();
    }
  }

  Future<void> _downloadFile(
    LocalModelFile file,
    File target,
    _DownloadJob job,
    void Function(int received) onBytes,
  ) async {
    final part = File('${target.path}.part');
    final response = await _client.send(http.Request('GET', file.uri));
    if (response.statusCode != HttpStatus.ok) {
      await response.stream.drain<void>();
      throw ModelDownloadException(
        'Download of ${file.name} failed with HTTP ${response.statusCode}',
      );
    }
    final digest = _DigestSink._(file.sha256 ?? file.gitBlobSha1);
    final hash = file.sha256 != null
        ? sha256.startChunkedConversion(digest)
        : (sha1.startChunkedConversion(digest)..add(gitBlobHeader(file.size)));
    final sink = part.openWrite();
    var sinkClosed = false;
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        if (job.cancelled) throw const _Cancelled();
        received += chunk.length;
        if (received > file.size) {
          throw ModelVerificationException(
            '${file.name} is larger than the expected ${file.size} bytes',
          );
        }
        sink.add(chunk);
        hash.add(chunk);
        onBytes(received);
      }
      await sink.close();
      sinkClosed = true;
      hash.close();
      if (received != file.size) {
        throw ModelVerificationException(
          '${file.name} has $received bytes, expected ${file.size}',
        );
      }
      if (!digest.matches) {
        throw ModelVerificationException(
          '${file.name} does not match its pinned checksum',
        );
      }
      await part.rename(target.path);
    } catch (_) {
      if (!sinkClosed) await sink.close();
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  Future<bool> _allPresent(LocalModelSpec model) async {
    for (final file in model.files) {
      if (!await _isComplete(File(_filePath(model, file)), file)) return false;
    }
    return true;
  }

  Future<bool> _isComplete(File target, LocalModelFile file) async =>
      await target.exists() && await target.length() == file.size;

  String _modelDir(LocalModelSpec model) => '$modelsDir/${model.id}';

  String _filePath(LocalModelSpec model, LocalModelFile file) =>
      '${_modelDir(model)}/${file.name}';

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }
}

/// [LocalModelService] for the settings screen, on top of
/// [PlatformLocalModelFiles].
class PlatformLocalModelService implements LocalModelService {
  PlatformLocalModelService(this._files);

  final PlatformLocalModelFiles _files;

  @override
  Stream<List<LocalModelInfo>> watch() {
    StreamSubscription<void>? changes;
    var pending = Future<void>.value();
    late final StreamController<List<LocalModelInfo>> controller;

    void push() {
      pending = pending.then((_) async {
        final snapshot = await _snapshot();
        if (!controller.isClosed) controller.add(snapshot);
      });
    }

    controller = StreamController<List<LocalModelInfo>>(
      onListen: () {
        changes = _files.changes.listen((_) => push());
        push();
      },
      onCancel: () async {
        await changes?.cancel();
        await controller.close();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> download(String modelId) async {
    await for (final _ in _files.download(modelId)) {}
  }

  @override
  Future<void> remove(String modelId) => _files.remove(modelId);

  Future<List<LocalModelInfo>> _snapshot() async => [
    for (final model in _files.catalog)
      LocalModelInfo(
        id: model.id,
        displayName: model.displayName,
        sizeBytes: model.totalBytes,
        state: await _files.state(model.id),
        progress: _files.progress(model.id),
      ),
  ];
}

class _DownloadJob {
  final controller = StreamController<double>.broadcast();
  final done = Completer<void>();
  double progress = 0;
  bool cancelled = false;

  Stream<double> get progressStream => controller.stream;

  /// Emits in steps of at least 1% so a 34 MB download doesn't flood
  /// listeners with thousands of events.
  void report(double value, void Function() notify) {
    if (value < 1 && value - progress < 0.01) return;
    progress = value;
    if (!controller.isClosed) controller.add(value);
    notify();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class _DigestSink implements Sink<Digest> {
  _DigestSink._(this.expected);

  final String? expected;
  Digest? _value;

  Digest get value => _value!;

  bool get matches =>
      _value != null && _value.toString() == expected?.toLowerCase();

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}
