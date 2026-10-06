// Bridge between the Flutter app and the Android layer.
//
// This file is the source of truth. After editing it, regenerate with:
//   cd app && dart run pigeon --input pigeons/messages.dart && dart format lib/src/platform
// and commit both generated files.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/platform/messages.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'android/app/src/main/kotlin/io/github/gameon223/memora/bridge/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'io.github.gameon223.memora.bridge'),
  ),
)
// ---------------------------------------------------------------------------
// Gallery
// ---------------------------------------------------------------------------
enum GalleryPermission {
  /// Full access to images.
  granted,

  /// Android 14+ partial access to images the user picked.
  partial,
  denied,

  /// Denied and Android will no longer show the prompt.
  permanentlyDenied,
}

class GalleryImage {
  GalleryImage({
    required this.uri,
    required this.takenAtMillis,
    required this.width,
    required this.height,
    required this.byteSize,
    required this.mimeType,
  });

  /// `content://` URI.
  String uri;
  int takenAtMillis;
  int width;
  int height;
  int byteSize;
  String mimeType;
}

class GalleryPage {
  GalleryPage({required this.images, required this.hasMore});

  List<GalleryImage> images;
  bool hasMore;
}

/// A file copied into app storage.
class CopiedImage {
  CopiedImage({
    required this.sourceUri,
    required this.relativePath,
    required this.sha256,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.byteSize,
    required this.takenAtMillis,
  });

  String sourceUri;

  /// Relative to the app files dir, for example `originals/<uuid>.png`.
  String relativePath;
  String sha256;
  String mimeType;
  int width;
  int height;
  int byteSize;
  int takenAtMillis;
}

class CopyFailure {
  CopyFailure({required this.sourceUri, required this.message});

  String sourceUri;
  String message;
}

class CopyResult {
  CopyResult({required this.copied, required this.failed});

  List<CopiedImage> copied;
  List<CopyFailure> failed;
}

@HostApi()
abstract class GalleryHostApi {
  GalleryPermission permissionState();

  @async
  GalleryPermission requestPermission();

  void openAppSettings();

  /// Images newest taken first.
  @async
  GalleryPage listImages(int offset, int limit);

  /// JPEG bytes no larger than [size] on the long edge.
  @async
  Uint8List thumbnail(String uri, int size);

  /// Opens the system Photo Picker. Returns selected content URIs.
  @async
  List<String> pickWithSystemPicker(int maxItems);

  /// Streams each URI into `files/originals/` and reports file facts.
  @async
  CopyResult copyToAppStorage(List<String> uris);

  /// Writes a thumbnail for an image already in app storage. Returns the
  /// relative path of the thumbnail.
  @async
  String createThumbnail(String relativeSourcePath, int maxEdge);
}

// ---------------------------------------------------------------------------
// Capture (Quick Settings tile, accessibility, share)
// ---------------------------------------------------------------------------
class CaptureStatus {
  CaptureStatus({
    required this.accessibilitySupported,
    required this.accessibilityEnabled,
    required this.canRequestTile,
    required this.notificationsAllowed,
  });

  /// Android 11 or newer.
  bool accessibilitySupported;
  bool accessibilityEnabled;

  /// Android 13+ can prompt to add the tile directly.
  bool canRequestTile;
  bool notificationsAllowed;
}

/// A capture or share waiting in `files/inbox/`.
class InboxItem {
  InboxItem({
    required this.id,
    required this.relativePath,
    required this.source,
    required this.capturedAtMillis,
    required this.sha256,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.byteSize,
  });

  /// Inbox id, passed back to [CaptureHostApi.confirmInbox] once the memory
  /// row exists.
  String id;
  String relativePath;

  /// `tile` or `share`.
  String source;
  int capturedAtMillis;
  String sha256;
  String mimeType;
  int width;
  int height;
  int byteSize;
}

@HostApi()
abstract class CaptureHostApi {
  CaptureStatus status();

  void openAccessibilitySettings();

  /// Android 13+: asks the system to add the Memora tile.
  @async
  bool requestAddTile();

  @async
  bool requestNotificationPermission();

  /// Moves inbox files into `originals/` and returns their facts. Items stay
  /// in the inbox until [confirmInbox] acknowledges them, so a capture
  /// survives a worker that is stopped halfway.
  @async
  List<InboxItem> drainInbox();

  /// Drops inbox entries whose memories now exist. Anything left unconfirmed
  /// is offered again by the next [drainInbox].
  @async
  void confirmInbox(List<String> ids);
}

// ---------------------------------------------------------------------------
// Background processing
// ---------------------------------------------------------------------------
class SchedulePolicy {
  SchedulePolicy({
    required this.immediate,
    required this.paused,
    required this.windowStartMinutes,
    required this.windowEndMinutes,
    required this.requiresUnmeteredNetwork,
    required this.hasWork,
  });

  bool immediate;
  bool paused;
  int windowStartMinutes;
  int windowEndMinutes;

  /// True when a selected capability sends data off the device.
  bool requiresUnmeteredNetwork;

  /// False lets the scheduler cancel pending work.
  bool hasWork;
}

@HostApi()
abstract class SchedulerHostApi {
  /// Replaces pending processing work to match [policy].
  void apply(SchedulePolicy policy);

  /// Runs the queue now, ignoring the time window, for this batch only.
  void processNow(bool requiresUnmeteredNetwork);

  void cancelAll();
}

class RunResult {
  RunResult({required this.processed, required this.remaining});

  int processed;
  bool remaining;
}

/// Called by Android workers on the headless engine.
@FlutterApi()
abstract class BackgroundFlutterApi {
  @async
  int ingestInbox();

  @async
  RunResult runQueue(int budgetMillis, bool processNow);

  @async
  int reindexEmbeddings(int budgetMillis);
}

/// Called by the headless Dart entrypoint once it can receive calls.
@HostApi()
abstract class BackgroundHostApi {
  void backgroundReady();

  /// The entrypoint could not build its services. Ends the worker right away
  /// instead of waiting for the readiness timeout.
  void backgroundFailed(String message);
}

// ---------------------------------------------------------------------------
// Secrets
// ---------------------------------------------------------------------------
@HostApi()
abstract class SecretHostApi {
  String? read(String key);

  void write(String key, String value);

  void delete(String key);

  List<String> keys();
}

// ---------------------------------------------------------------------------
// On-device inference
// ---------------------------------------------------------------------------
class OcrLineMessage {
  OcrLineMessage({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  String text;
  int left;
  int top;
  int right;
  int bottom;
}

class OcrBlockMessage {
  OcrBlockMessage({required this.lines});

  List<OcrLineMessage> lines;
}

@HostApi()
abstract class OcrHostApi {
  @async
  List<OcrBlockMessage> recognize(String absolutePath);
}

class TokenBatch {
  TokenBatch({
    required this.inputIds,
    required this.attentionMask,
    required this.tokenTypeIds,
    required this.sequenceLength,
  });

  /// Row-major, batch size times [sequenceLength].
  Int64List inputIds;
  Int64List attentionMask;
  Int64List tokenTypeIds;
  int sequenceLength;
}

@HostApi()
abstract class EmbeddingHostApi {
  @async
  void load(String absoluteModelPath);

  bool isLoaded();

  /// Returns batch size times dimensions values, row-major, L2-normalized.
  /// Pigeon has no Float32List, so values cross the bridge as doubles.
  @async
  Float64List run(TokenBatch batch);
}

// ---------------------------------------------------------------------------
// On-device generative models
// ---------------------------------------------------------------------------

/// What the device has to spare right now. Read before loading a model that
/// is measured in gigabytes.
class DeviceMemory {
  DeviceMemory({
    required this.totalBytes,
    required this.availableBytes,
    required this.lowRamDevice,
  });

  int totalBytes;
  int availableBytes;
  bool lowRamDevice;
}

/// A model file the user brought in, living under `files/models/imported/`.
class ImportedModel {
  ImportedModel({
    required this.relativePath,
    required this.fileName,
    required this.byteSize,
  });

  /// Relative to the app files dir, for example
  /// `models/imported/gemma-3-1b-it-int4.task`.
  String relativePath;
  String fileName;
  int byteSize;
}

/// One piece of a generation. [text] is the new text only, not the whole
/// answer so far. The last chunk for a request has [done] set, and carries
/// [error] when the generation failed partway.
class LlmChunk {
  LlmChunk({
    required this.requestId,
    required this.text,
    required this.done,
    this.error,
  });

  int requestId;
  String text;
  bool done;
  String? error;
}

@HostApi()
abstract class LlmHostApi {
  /// Loads a model file from app storage. Safe to call again with the same
  /// path and settings. Loading a different model unloads the previous one.
  @async
  void load(String relativeModelPath, bool vision, int maxTokens);

  bool isLoaded();

  String? loadedModelPath();

  @async
  void unload();

  /// Starts generation and returns a request id. Text arrives on the event
  /// channel. Images are only accepted when the model was loaded with vision.
  @async
  int startGeneration(String prompt, List<Uint8List> images, int maxTokens);

  void cancelGeneration(int requestId);

  DeviceMemory deviceMemory();
}

/// How far the copy behind [ModelImportHostApi.pickModelFile] has got.
///
/// [totalBytes] is the size the picked file claims, and zero when the source
/// would not say. A model is measured in gigabytes and the copy runs for
/// minutes, so this is what keeps the import from looking stuck.
class ModelImportProgress {
  ModelImportProgress({required this.copiedBytes, required this.totalBytes});

  int copiedBytes;
  int totalBytes;
}

@EventChannelApi()
abstract class LlmEvents {
  LlmChunk chunks();

  ModelImportProgress importProgress();
}

@HostApi()
abstract class ModelImportHostApi {
  /// Opens the system file picker for a model file and copies the chosen one
  /// into app storage under models/. Returns null if the user cancels.
  @async
  ImportedModel? pickModelFile();

  @async
  void deleteModel(String relativePath);

  List<ImportedModel> listModels();
}

// ---------------------------------------------------------------------------
// Files
// ---------------------------------------------------------------------------
@HostApi()
abstract class FilesHostApi {
  /// Absolute path of the app files directory.
  String filesDir();

  /// Opens the system "save as" dialog and copies [absoluteSourcePath] to the
  /// chosen location. Returns false if the user cancelled.
  @async
  bool saveToUserLocation(
    String absoluteSourcePath,
    String suggestedName,
    String mimeType,
  );
}
