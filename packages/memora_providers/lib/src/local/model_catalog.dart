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

/// A generative model the user brings themselves.
///
/// Gemma is published under terms you accept on the model's own page before
/// the download link appears, so Memora cannot fetch one of these files for
/// the user the way it fetches the embedding model. Settings links to
/// [sourceUrl] and imports the file the user downloaded, which is why these
/// entries carry no URL to a weights file and no checksum.
///
/// Sizes are approximate: the published files are rebuilt from time to time
/// and the figure is here to set expectations before a long download, not to
/// verify anything.
class LocalLlmSpec {
  const LocalLlmSpec({
    required this.id,
    required this.displayName,
    required this.approximateBytes,
    required this.vision,
    required this.requiredMemoryBytes,
    required this.adds,
    required this.sourceName,
    required this.sourceUrl,
    required this.licence,
    this.fileExtensions = const ['.task'],
    this.maxTokens = 4096,
  });

  /// Stable id, stored in settings as the model of a capability.
  final String id;
  final String displayName;

  /// Roughly how large the file the user downloads is.
  final int approximateBytes;

  /// Whether the model reads images, which decides if it can serve vision.
  final bool vision;

  /// RAM the model realistically needs while it is loaded. A phone with
  /// less than this cannot run it, whatever the file size suggests.
  final int requiredMemoryBytes;

  /// One line on what installing this adds, for the settings row.
  final String adds;

  /// Where the file comes from, for example `Hugging Face`.
  final String sourceName;
  final String sourceUrl;

  /// The licence the user accepts on [sourceUrl] before downloading.
  final String licence;

  /// File name endings the model is published with. Anything else is
  /// refused on import.
  final List<String> fileExtensions;

  /// Context size the runtime is loaded with, covering prompt and reply.
  final int maxTokens;
}

/// Gemma 3 1B, 4-bit, text only. The smallest model that answers in
/// sentences on a mid-range phone.
const gemma3_1b = LocalLlmSpec(
  id: 'gemma-3-1b-it-int4',
  displayName: 'Gemma 3 1B',
  approximateBytes: 550 * 1024 * 1024,
  vision: false,
  requiredMemoryBytes: 2 * 1024 * 1024 * 1024,
  adds: 'Answers questions about your memories in its own words.',
  sourceName: 'Hugging Face',
  sourceUrl: 'https://huggingface.co/litert-community/Gemma3-1B-IT',
  licence: 'Gemma Terms of Use',
);

/// Gemma 3n E2B, 4-bit, text and images. Large enough to replace the OCR
/// vision path, and large enough that most phones cannot hold it.
const gemma3nE2b = LocalLlmSpec(
  id: 'gemma-3n-e2b-it-int4',
  displayName: 'Gemma 3n E2B',
  approximateBytes: 3 * 1024 * 1024 * 1024,
  vision: true,
  requiredMemoryBytes: 4 * 1024 * 1024 * 1024,
  adds: 'Answers questions and reads images, so vision runs here too.',
  sourceName: 'Hugging Face',
  sourceUrl: 'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview',
  licence: 'Gemma Terms of Use',
);

/// Generative models settings offers, smallest first.
const localLlmCatalog = [gemma3_1b, gemma3nE2b];

LocalLlmSpec? localLlmSpec(String id) {
  for (final spec in localLlmCatalog) {
    if (spec.id == id) return spec;
  }
  return null;
}
