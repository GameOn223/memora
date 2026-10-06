import 'dart:async';

import 'package:flutter/services.dart';
import 'package:memora_core/memora_core.dart';

import '../platform/messages.g.dart' as bridge;

/// [LocalLlmRuntime] over the MediaPipe runtime on the Kotlin side.
///
/// Generated text arrives on one event channel shared by every request, so a
/// generation listens before it starts and keeps the pieces whose request id
/// is its own. Cancelling the Dart stream cancels the request, which is how
/// a reply that has already said everything it needs to stops costing
/// tokens.
class BridgeLocalLlmRuntime implements LocalLlmRuntime {
  BridgeLocalLlmRuntime({
    bridge.LlmHostApi? host,
    Stream<bridge.LlmChunk>? chunks,
  }) : _host = host ?? bridge.LlmHostApi(),
       _chunks = chunks ?? bridge.chunks();

  static const providerId = 'local';

  final bridge.LlmHostApi _host;
  final Stream<bridge.LlmChunk> _chunks;

  @override
  Future<void> load(
    String relativeModelPath, {
    required bool vision,
    int maxTokens = 4096,
  }) async {
    try {
      await _host.load(relativeModelPath, vision, maxTokens);
    } on PlatformException catch (error) {
      throw loadFailure(error);
    }
  }

  @override
  Future<bool> isLoaded() async {
    try {
      return await _host.isLoaded();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<String?> loadedModelPath() async {
    try {
      return await _host.loadedModelPath();
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> unload() async {
    try {
      await _host.unload();
    } on PlatformException {
      // Nothing to free, or the engine is already gone.
    }
  }

  @override
  Stream<String> generate(
    String prompt, {
    List<Uint8List> images = const [],
    int maxTokens = 1024,
  }) {
    final out = StreamController<String>();
    final early = <bridge.LlmChunk>[];
    StreamSubscription<bridge.LlmChunk>? listening;
    int? requestId;

    void deliver(bridge.LlmChunk chunk) {
      if (out.isClosed) return;
      if (chunk.error case final message?) {
        out.addError(
          AiTransientException(message, providerId: providerId),
          StackTrace.current,
        );
        unawaited(out.close());
        return;
      }
      if (chunk.text.isNotEmpty) out.add(chunk.text);
      if (chunk.done) unawaited(out.close());
    }

    // Listening first, because the first piece can arrive before the call
    // that starts the generation has returned its id.
    listening = _chunks.listen(
      (chunk) {
        if (requestId == null) {
          early.add(chunk);
        } else if (chunk.requestId == requestId) {
          deliver(chunk);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!out.isClosed) out.addError(_failure(error), stack);
      },
    );

    out.onCancel = () async {
      await listening?.cancel();
      final id = requestId;
      if (id == null) return;
      try {
        await _host.cancelGeneration(id);
      } on PlatformException {
        // The generation had already finished.
      }
    };

    unawaited(
      _host
          .startGeneration(prompt, images, maxTokens)
          .then((id) {
            requestId = id;
            for (final chunk in early) {
              if (chunk.requestId == id) deliver(chunk);
            }
            early.clear();
          })
          .onError<Object>((error, stack) {
            if (out.isClosed) return;
            out.addError(_failure(error), stack);
            unawaited(out.close());
          }),
    );

    return out.stream;
  }

  @override
  Future<DeviceMemory> memory() async {
    final reported = await _host.deviceMemory();
    return DeviceMemory(
      totalBytes: reported.totalBytes,
      availableBytes: reported.availableBytes,
      lowRamDevice: reported.lowRamDevice,
    );
  }

  /// Why a load failed, in terms the queue and the UI already handle.
  ///
  /// A phone that cannot hold the model will not hold it on the next
  /// attempt either, so that is a configuration problem the user settles by
  /// choosing a smaller model. Running out of free memory, or a generation
  /// already in flight, passes with time.
  static AiException loadFailure(PlatformException error) {
    final message = error.message ?? 'The model could not be loaded.';
    return switch (error.code) {
      'low_ram_device' || 'model_too_large' || 'max_tokens_too_large' =>
        AiConfigurationException(message, providerId: providerId),
      _ => AiTransientException(message, providerId: providerId),
    };
  }

  static Object _failure(Object error) => error is AiException
      ? error
      : AiTransientException(
          error is PlatformException
              ? error.message ?? error.code
              : 'The on-device model stopped: $error',
          providerId: providerId,
        );
}

/// [LocalLlmFiles] over the system file picker on the Kotlin side.
///
/// Kotlin names the copied file after the file the user picked, and a model
/// file name says nothing dependable about which build it holds. So the
/// catalog id the user was importing is recorded against the path it landed
/// at, and [installed] reconciles that record with the files actually there.
/// A file removed from outside the app drops out of the record on the next
/// read.
class BridgeLocalLlmFiles implements LocalLlmFiles {
  BridgeLocalLlmFiles({
    required this._settings,
    bridge.ModelImportHostApi? host,
    Stream<bridge.ModelImportProgress>? progress,
  }) : _host = host ?? bridge.ModelImportHostApi(),
       _progress = progress ?? bridge.importProgress();

  /// Settings key holding `{model id: relative path}`.
  static const settingsKey = 'local_llm.imported';

  final SettingsStore _settings;
  final bridge.ModelImportHostApi _host;
  final Stream<bridge.ModelImportProgress> _progress;

  @override
  Future<List<InstalledLlmModel>> installed() async {
    final record = await _record();
    if (record.isEmpty) return const [];
    final onDisk = {
      for (final file in await _host.listModels()) file.relativePath: file,
    };
    final result = <InstalledLlmModel>[];
    final kept = <String, String>{};
    for (final entry in record.entries) {
      final file = onDisk[entry.value];
      if (file == null) continue;
      kept[entry.key] = entry.value;
      result.add(
        InstalledLlmModel(
          modelId: entry.key,
          relativePath: file.relativePath,
          sizeBytes: file.byteSize,
        ),
      );
    }
    if (kept.length != record.length) await _write(kept);
    return result;
  }

  /// Opens the picker, copies the file in and reports how far the copy has
  /// got on the way.
  ///
  /// The call that starts the copy only returns once the file is whole, so
  /// progress has to come from the event channel while that call is still
  /// outstanding. A source that would not say how large it is reports no
  /// fraction, and the UI shows a bar with no end rather than a wrong one.
  @override
  Stream<ModelImportEvent> import(
    String modelId, {
    required List<String> extensions,
  }) {
    final out = StreamController<ModelImportEvent>();
    final watching = _progress.listen((report) {
      if (out.isClosed || report.totalBytes <= 0) return;
      final fraction = report.copiedBytes / report.totalBytes;
      out.add(ModelImportCopying(fraction.clamp(0.0, 1.0)));
    }, onError: (Object _) {});

    unawaited(
      _pickAndRecord(modelId)
          .then((event) {
            if (!out.isClosed) out.add(event);
          })
          .onError<Object>((error, stack) {
            if (!out.isClosed) out.addError(error, stack);
          })
          .whenComplete(() async {
            await watching.cancel();
            await out.close();
          }),
    );
    out.onCancel = watching.cancel;
    return out.stream;
  }

  /// The import itself, which ends in exactly one event.
  Future<ModelImportEvent> _pickAndRecord(String modelId) async {
    bridge.ImportedModel? picked;
    try {
      picked = await _host.pickModelFile();
    } on PlatformException catch (error) {
      return ModelImportRefused(refusalFor(error.code));
    }
    if (picked == null) return const ModelImportCancelled();
    final record = await _record();
    // Importing over an earlier file for the same entry leaves the old one
    // behind, and a spare three gigabytes is not something to keep quietly.
    final previous = record[modelId];
    if (previous != null && previous != picked.relativePath) {
      try {
        await _host.deleteModel(previous);
      } on PlatformException {
        // It was already gone.
      }
    }
    await _write({...record, modelId: picked.relativePath});
    return ModelImportDone(
      InstalledLlmModel(
        modelId: modelId,
        relativePath: picked.relativePath,
        sizeBytes: picked.byteSize,
      ),
    );
  }

  @override
  Future<void> remove(String modelId) async {
    final record = await _record();
    final path = record[modelId];
    if (path == null) return;
    try {
      await _host.deleteModel(path);
    } on PlatformException {
      // Already gone. The record still has to go.
    }
    await _write({...record}..remove(modelId));
  }

  /// What the picker refused, from the code Kotlin sent.
  static ModelImportRefusal refusalFor(String code) => switch (code) {
    'unsupported_model' => ModelImportRefusal.wrongFileType,
    'no_space' => ModelImportRefusal.notEnoughStorage,
    _ => ModelImportRefusal.unreadable,
  };

  Future<Map<String, String>> _record() async {
    final raw = await _settings.read(settingsKey);
    if (raw is! Map) return {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  Future<void> _write(Map<String, String> record) =>
      _settings.write(settingsKey, record.isEmpty ? null : record);
}
