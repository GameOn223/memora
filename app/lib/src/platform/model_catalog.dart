import 'package:flutter/foundation.dart';

/// One file of an on-device model, pinned to an exact upstream revision.
///
/// Every file carries either a SHA-256 or a git blob SHA-1. Hugging Face
/// reports LFS files by SHA-256 and small files by their git blob id.
@immutable
class LocalModelFile {
  const LocalModelFile({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
    this.gitBlobSha1,
  }) : assert(sha256 != null || gitBlobSha1 != null);

  final String name;
  final String url;
  final int size;
  final String? sha256;
  final String? gitBlobSha1;

  Uri get uri => Uri.parse(url);
}

@immutable
class LocalModelSpec {
  const LocalModelSpec({
    required this.id,
    required this.displayName,
    required this.revision,
    required this.files,
    required this.dimensions,
  });

  final String id;
  final String displayName;
  final String revision;
  final List<LocalModelFile> files;
  final int dimensions;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);
}

// Same values as the catalog in memora_providers. Kept here until that
// package exports it, then this file can re-export the shared constant.
const bgeSmallEnV15 = LocalModelSpec(
  id: 'bge-small-en-v1.5',
  displayName: 'bge-small-en v1.5',
  revision: 'ea104dacec62c0de699686887e3f920caeb4f3e3',
  dimensions: 384,
  files: [
    LocalModelFile(
      name: 'model_quantized.onnx',
      url:
          'https://huggingface.co/Xenova/bge-small-en-v1.5/resolve/'
          'ea104dacec62c0de699686887e3f920caeb4f3e3/onnx/model_quantized.onnx',
      size: 34014426,
      sha256:
          '6c9c6101a956d62dfb5e7190c538226c0c5bb9cb27b651234b6df063ee7dbfe4',
    ),
    LocalModelFile(
      name: 'vocab.txt',
      url:
          'https://huggingface.co/Xenova/bge-small-en-v1.5/resolve/'
          'ea104dacec62c0de699686887e3f920caeb4f3e3/vocab.txt',
      size: 231508,
      gitBlobSha1: 'fb140275c155a9c7c5a3b3e0e77a9e839594a938',
    ),
  ],
);

const localModelCatalog = <LocalModelSpec>[bgeSmallEnV15];
