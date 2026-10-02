/// Android adapters for the core ports and the app services.
///
/// The composition root in `bootstrap/` builds these; nothing else in the app
/// should import the generated bridge in `messages.g.dart` directly.
library;

export 'app_paths.dart' show resolveInside;
export 'background_entry.dart';
export 'local_model_files.dart';
export 'platform_capture_service.dart' show PlatformCaptureService;
export 'platform_embedding_runtime.dart' show PlatformEmbeddingRuntime;
export 'platform_export_service.dart' show PlatformExportService;
export 'platform_gallery_service.dart' show PlatformGalleryService;
export 'platform_image_files.dart' show PlatformImageFiles;
export 'platform_ocr_engine.dart' show PlatformOcrEngine;
export 'platform_queue_scheduler.dart' show PlatformQueueScheduler;
export 'platform_secret_store.dart' show PlatformSecretStore;
