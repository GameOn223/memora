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
