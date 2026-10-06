import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Wall clock, injectable for tests.
abstract interface class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// Generates unique ids. The app uses UUID v4.
abstract interface class IdGenerator {
  String next();
}

/// File access for images in app storage. Paths are relative to the app's
/// files directory.
abstract interface class ImageFiles {
  Future<Uint8List> readBytes(String relativePath);

  /// Writes a thumbnail for [sourcePath] no larger than [maxEdge] pixels on
  /// its long edge. Returns the relative path of the thumbnail.
  Future<String> createThumbnail(String sourcePath, {int maxEdge = 512});

  /// Deletes files, ignoring any that are already gone.
  Future<void> delete(List<String> relativePaths);

  String absolutePath(String relativePath);
}

/// A recognized line of text with its bounding box in image pixels.
@immutable
class OcrLine {
  const OcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final int left;
  final int top;
  final int right;
  final int bottom;

  int get height => bottom - top;
}

@immutable
class OcrBlock {
  const OcrBlock({required this.lines});

  final List<OcrLine> lines;

  String get text => lines.map((l) => l.text).join('\n');
}

@immutable
class OcrResult {
  const OcrResult({required this.blocks});

  final List<OcrBlock> blocks;

  String get text => blocks.map((b) => b.text).join('\n\n');

  bool get isEmpty => blocks.every((b) => b.lines.isEmpty);
}

/// On-device text recognition. Implemented with ML Kit.
abstract interface class OcrEngine {
  Future<OcrResult> recognize(String absoluteImagePath);
}

/// Token ids for one input, as produced by a tokenizer.
@immutable
class EncodedText {
  const EncodedText({
    required this.inputIds,
    required this.attentionMask,
    required this.tokenTypeIds,
  });

  final Int64List inputIds;
  final Int64List attentionMask;
  final Int64List tokenTypeIds;
}

/// Runs an ONNX sentence embedding model on device.
abstract interface class EmbeddingRuntime {
  /// Loads the model file. Safe to call again with the same path.
  Future<void> load(String absoluteModelPath);

  Future<bool> isLoaded();

  /// Returns one L2-normalized vector per input, using CLS pooling.
  Future<List<Float32List>> run(List<EncodedText> batch);
}

/// What the device can offer a large model right now.
@immutable
class DeviceMemory {
  const DeviceMemory({
    required this.totalBytes,
    required this.availableBytes,
    required this.lowRamDevice,
  });

  /// Physical RAM on the device.
  final int totalBytes;

  /// RAM the system says is free for a new allocation right now.
  final int availableBytes;

  /// Android's own low-memory flag. A model that fits on paper still has to
  /// be refused on one of these phones.
  final bool lowRamDevice;
}

/// A generative model running on this device.
abstract interface class LocalLlmRuntime {
  /// Loads a model file already in app storage. Safe to call again with the
  /// same path and settings.
  Future<void> load(
    String relativeModelPath, {
    required bool vision,
    int maxTokens,
  });

  Future<bool> isLoaded();

  Future<String?> loadedModelPath();

  Future<void> unload();

  /// Generated text, a piece at a time. Images are only accepted when the
  /// model was loaded with vision.
  Stream<String> generate(
    String prompt, {
    List<Uint8List> images,
    int maxTokens,
  });

  Future<DeviceMemory> memory();
}

/// A generative model file sitting in app storage.
@immutable
class InstalledLlmModel {
  const InstalledLlmModel({
    required this.modelId,
    required this.relativePath,
    required this.sizeBytes,
  });

  /// Catalog id the file was imported as.
  final String modelId;

  /// Path inside the app's files directory, as [LocalLlmRuntime.load] takes
  /// it.
  final String relativePath;
  final int sizeBytes;
}

/// Progress of bringing a model file in, from the system picker to a file in
/// app storage.
sealed class ModelImportEvent {
  const ModelImportEvent();
}

/// Copying, from 0 to 1.
final class ModelImportCopying extends ModelImportEvent {
  const ModelImportCopying(this.fraction);

  final double fraction;
}

final class ModelImportDone extends ModelImportEvent {
  const ModelImportDone(this.model);

  final InstalledLlmModel model;
}

/// The picker closed without a file.
final class ModelImportCancelled extends ModelImportEvent {
  const ModelImportCancelled();
}

/// Why a model file cannot be used. Trying the same thing again would end
/// the same way, so the UI says what to do instead of offering a retry.
/// [downloadFailed] is the exception and does offer one.
enum ModelImportRefusal {
  wrongFileType,
  notEnoughStorage,
  unreadable,

  /// No access token saved, or the one saved was rejected.
  tokenRejected,

  /// The token is good, but the account behind it has not been granted
  /// access to this repository's files.
  licenceNotAccepted,

  /// Hugging Face could not be reached, or the transfer broke partway.
  downloadFailed,
}

final class ModelImportRefused extends ModelImportEvent {
  const ModelImportRefused(this.reason, {this.fileName});

  final ModelImportRefusal reason;

  /// Name of the file the user picked, when the picker reported one.
  final String? fileName;
}

/// Model files the user brings in themselves. The platform layer opens the
/// system picker and copies the chosen file into app storage.
abstract interface class LocalLlmFiles {
  /// Model files in app storage.
  Future<List<InstalledLlmModel>> installed();

  /// Opens the system picker, then copies the chosen file into app storage
  /// as [modelId]. [extensions] are the endings the model is published with,
  /// such as `.task`, and anything else is refused.
  Stream<ModelImportEvent> import(
    String modelId, {
    required List<String> extensions,
  });

  /// Downloads [modelId] straight from the repository it is published in,
  /// authenticating with [token].
  ///
  /// The weights are behind a licence the user accepts on the model's own
  /// page, so there is no link that works without a token. What lands in app
  /// storage is the same file an import would have produced, which is why
  /// this reports the same events.
  Stream<ModelImportEvent> download(String modelId, {required String token});

  Future<void> remove(String modelId);
}

/// State of an on-device model download.
enum LocalModelState { notDownloaded, downloading, ready, failed }

/// Manages files for on-device models such as the embedding model.
abstract interface class LocalModelFiles {
  Future<LocalModelState> state(String modelId);

  /// Absolute path of a downloaded, verified file for [modelId].
  Future<String?> path(String modelId, String fileName);

  /// Downloads and verifies every file for [modelId]. Emits progress 0 to 1.
  Stream<double> download(String modelId);

  Future<void> remove(String modelId);
}
