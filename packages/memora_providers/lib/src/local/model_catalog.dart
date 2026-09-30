/// On-device model files Memora can download, pinned to exact upstream
/// revisions and checked against known hashes before they're loaded.
library;

class LocalModelFile {
  const LocalModelFile({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
    this.gitBlobSha1,
  });

  /// File name inside the model's folder, for example `vocab.txt`.
  final String name;

  /// Download URL at a pinned revision. Kept as text so specs can be const.
  final String url;

  /// Exact size in bytes.
  final int size;

  /// SHA-256 of the file, for files stored with Git LFS.
  final String? sha256;

  /// Git blob SHA-1, for small files stored directly in the repository.
  /// It hashes `blob <size>\0` followed by the content.
  final String? gitBlobSha1;

  Uri get uri => Uri.parse(url);
}

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

  /// Upstream commit every file URL points at.
  final String revision;
  final List<LocalModelFile> files;

  /// Length of the vectors the model produces.
  final int dimensions;

  LocalModelFile? file(String name) {
    for (final f in files) {
      if (f.name == name) return f;
    }
    return null;
  }

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);
}

/// File names of the embedding model inside its folder.
const onnxModelFileName = 'model_quantized.onnx';
const vocabFileName = 'vocab.txt';

/// bge-small-en-v1.5 with int8 weights, from the Xenova ONNX export.
const bgeSmallEnV15 = LocalModelSpec(
  id: 'bge-small-en-v1.5',
  displayName: 'bge-small-en v1.5',
  revision: 'ea104dacec62c0de699686887e3f920caeb4f3e3',
  dimensions: 384,
  files: [
    LocalModelFile(
      name: onnxModelFileName,
      url:
          'https://huggingface.co/Xenova/bge-small-en-v1.5/resolve/'
          'ea104dacec62c0de699686887e3f920caeb4f3e3/onnx/model_quantized.onnx',
      size: 34014426,
      sha256:
          '6c9c6101a956d62dfb5e7190c538226c0c5bb9cb27b651234b6df063ee7dbfe4',
    ),
    LocalModelFile(
      name: vocabFileName,
      url:
          'https://huggingface.co/Xenova/bge-small-en-v1.5/resolve/'
          'ea104dacec62c0de699686887e3f920caeb4f3e3/vocab.txt',
      size: 231508,
      gitBlobSha1: 'fb140275c155a9c7c5a3b3e0e77a9e839594a938',
    ),
  ],
);

const localModelCatalog = [bgeSmallEnV15];

LocalModelSpec? localModelSpec(String id) {
  for (final spec in localModelCatalog) {
    if (spec.id == id) return spec;
  }
  return null;
}
