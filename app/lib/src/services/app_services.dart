import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';
import 'package:memora_providers/memora_providers.dart';

/// Everything the UI needs, built once by the composition root in
/// `bootstrap/`. Widget tests and screenshot tests use a fake implementation.
abstract interface class AppServices {
  MemoryStore get memories;
  QueueStore get queue;
  ConversationStore get conversations;
  SettingsStore get settings;
  SecretStore get secrets;
  ImageFiles get images;

  ProviderRegistry get providers;
  CapabilityRouter get router;
  AiSettingsRepository get aiSettings;

  MemoryIngestor get ingestor;
  ProcessingPipeline get pipeline;
  RetrievalEngine get retrieval;
  ChatEngine get chat;

  GalleryService get gallery;
  CaptureService get capture;
  QueueScheduler get scheduler;
  LocalModelService get localModels;

  /// The generative models the user can bring to this phone, with install
  /// state and what the device can hold.
  LocalLlmModels get localLlm;
  ExportService get export;
  AppPreferences get preferences;

  /// Opens a web page outside Memora: a model's licence, a provider's key
  /// settings. Every address is one Memora names itself.
  Links get links;
}

// ---------------------------------------------------------------------------
// Gallery
// ---------------------------------------------------------------------------

enum GalleryAccess { full, partial, denied, permanentlyDenied }

/// An image in the device gallery that can be added to Memora.
class DeviceImage {
  const DeviceImage({
    required this.uri,
    required this.takenAt,
    required this.width,
    required this.height,
    required this.byteSize,
    required this.mimeType,
  });

  final String uri;
  final DateTime takenAt;
  final int width;
  final int height;
  final int byteSize;
  final String mimeType;
}

class DeviceImagePage {
  const DeviceImagePage({required this.images, required this.hasMore});

  final List<DeviceImage> images;
  final bool hasMore;
}

class AddImagesResult {
  const AddImagesResult({
    required this.added,
    required this.duplicates,
    required this.failed,
  });

  final int added;
  final int duplicates;
  final int failed;
}

abstract interface class GalleryService {
  Future<GalleryAccess> access();

  Future<GalleryAccess> requestAccess();

  Future<void> openAppSettings();

  /// Newest taken first.
  Future<DeviceImagePage> list({required int offset, required int limit});

  Future<Uint8List> thumbnail(String uri, {int size = 256});

  /// System Photo Picker, for when gallery access is denied.
  Future<List<String>> pickWithSystemPicker({int maxItems = 100});

  /// Copies the images into app storage, files them as memories and nudges
  /// the scheduler. Never waits on AI.
  Future<AddImagesResult> addToMemora(List<String> uris);
}

// ---------------------------------------------------------------------------
// Capture
// ---------------------------------------------------------------------------

class CaptureSetup {
  const CaptureSetup({
    required this.accessibilitySupported,
    required this.accessibilityEnabled,
    required this.canRequestTile,
    required this.notificationsAllowed,
  });

  final bool accessibilitySupported;
  final bool accessibilityEnabled;
  final bool canRequestTile;
  final bool notificationsAllowed;
}

abstract interface class CaptureService {
  Future<CaptureSetup> setup();

  Future<void> openAccessibilitySettings();

  Future<bool> requestAddTile();

  Future<bool> requestNotificationPermission();

  /// Files tile captures and shared images waiting in the inbox. Returns how
  /// many memories were added.
  Future<int> ingestInbox();
}

// ---------------------------------------------------------------------------
// Queue scheduling
// ---------------------------------------------------------------------------

abstract interface class QueueScheduler {
  Future<QueuePolicy> policy();

  /// Saves the policy and reschedules native work to match.
  Future<void> setPolicy(QueuePolicy policy);

  /// Runs the queue now for this batch, ignoring the overnight window.
  Future<void> processNow();

  /// Re-reads settings and work state and reschedules. Call after adding
  /// images or changing providers.
  Future<void> refresh();
}

// ---------------------------------------------------------------------------
// On-device models
// ---------------------------------------------------------------------------

class LocalModelInfo {
  const LocalModelInfo({
    required this.id,
    required this.displayName,
    required this.sizeBytes,
    required this.state,
    this.progress,
  });

  final String id;
  final String displayName;
  final int sizeBytes;
  final LocalModelState state;

  /// 0 to 1 while downloading.
  final double? progress;
}

abstract interface class LocalModelService {
  Stream<List<LocalModelInfo>> watch();

  Future<void> download(String modelId);

  Future<void> remove(String modelId);
}

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------

class ExportProgress {
  const ExportProgress({required this.done, required this.total});

  final int done;
  final int total;
}

abstract interface class ExportService {
  /// Builds the export zip and opens the system save dialog. Completes with
  /// false if the user cancels.
  Future<bool> exportAll({void Function(ExportProgress progress)? onProgress});
}

// ---------------------------------------------------------------------------
// App preferences
// ---------------------------------------------------------------------------

enum ThemePreference { system, dark, light }

/// Small UI preferences stored in the settings table.
abstract interface class AppPreferences {
  Future<bool> onboardingComplete();

  Future<void> setOnboardingComplete();

  Future<ThemePreference> theme();

  Future<void> setTheme(ThemePreference theme);

  /// 2, 4 or 8 columns on the memories grid.
  Future<int> gridColumns();

  Future<void> setGridColumns(int columns);
}
