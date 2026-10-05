import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:memora_core/memora_core.dart';
import 'package:memora_database/memora_database.dart';
import 'package:memora_providers/memora_providers.dart';
import 'package:uuid/uuid.dart';

import '../platform/messages.g.dart';
import '../platform/platform.dart';
import '../services/app_services.dart';
import 'app_preferences_impl.dart';

/// UUID v4 ids for memories and conversations, as section 6.1 describes.
class UuidGenerator implements IdGenerator {
  const UuidGenerator();

  static const _uuid = Uuid();

  @override
  String next() => _uuid.v4();
}

/// The generated bridge APIs every Android adapter is built on.
///
/// This is the one place the app constructs them. Host tests pass fakes for
/// the ones the code under test reaches.
class PlatformHosts {
  PlatformHosts({
    FilesHostApi? files,
    GalleryHostApi? gallery,
    CaptureHostApi? capture,
    SchedulerHostApi? scheduler,
    SecretHostApi? secrets,
    OcrHostApi? ocr,
    EmbeddingHostApi? embedding,
  }) : files = files ?? FilesHostApi(),
       gallery = gallery ?? GalleryHostApi(),
       capture = capture ?? CaptureHostApi(),
       scheduler = scheduler ?? SchedulerHostApi(),
       secrets = secrets ?? SecretHostApi(),
       ocr = ocr ?? OcrHostApi(),
       embedding = embedding ?? EmbeddingHostApi();

  final FilesHostApi files;
  final GalleryHostApi gallery;
  final CaptureHostApi capture;
  final SchedulerHostApi scheduler;
  final SecretHostApi secrets;
  final OcrHostApi ocr;
  final EmbeddingHostApi embedding;
}

/// The real [AppServices]: a SQLite database in app storage, the shipped
/// providers behind a capability router, the core services from
/// `memora_core` and the Android adapters from `src/platform`.
///
/// Build one per isolate through `bootstrap.dart`. The UI engine and every
/// headless engine get their own, each with its own database connection.
class MemoraAppServices implements AppServices {
  MemoraAppServices({
    required this.database,
    required this.filesDir,
    required this.httpClient,
    required PlatformHosts hosts,
    this.clock = const SystemClock(),
    IdGenerator ids = const UuidGenerator(),
    Directory? exportCacheDirectory,
  }) {
    settings = database.settings;
    memories = database.memories;
    queue = database.queue;
    conversations = database.conversations;

    secrets = PlatformSecretStore(host: hosts.secrets);
    images = PlatformImageFiles(filesDir: filesDir, gallery: hosts.gallery);
    modelFiles = PlatformLocalModelFiles(
      modelsDir: resolveInside(filesDir, modelsFolder),
      client: httpClient,
    );
    localModels = PlatformLocalModelService(modelFiles);

    // The generative runtime comes from the platform layer. Until one is
    // wired in here, the provider offers no chat, vision stays on the OCR
    // path and settings leaves the model section out.
    localLlm = const LocalLlmModels();

    providers = ProviderRegistry();
    registerBuiltInProviders(
      providers,
      httpClient: httpClient,
      local: LocalRuntime(
        ocr: PlatformOcrEngine(host: hosts.ocr),
        embeddingRuntime: PlatformEmbeddingRuntime(host: hosts.embedding),
        modelFiles: modelFiles,
      ),
    );
    aiSettings = AiSettingsRepository(settings);
    router = CapabilityRouter(
      registry: providers,
      settings: aiSettings,
      secrets: secrets,
    );

    final policies = QueuePolicyRepository(settings);
    ingestor = DefaultMemoryIngestor(
      memories: memories,
      images: images,
      clock: clock,
      ids: ids,
    );
    pipeline = DefaultProcessingPipeline(
      queue: queue,
      memories: memories,
      vectors: database.vectors,
      router: router,
      images: images,
      policy: policies,
      clock: clock,
    );
    retrieval = DefaultRetrievalEngine(
      search: database.search,
      vectors: database.vectors,
      router: router,
    );
    chat = AgentChatEngine(
      conversations: conversations,
      router: router,
      retrieval: retrieval,
      search: database.search,
      vectors: database.vectors,
      memories: memories,
      images: images,
      aiSettings: aiSettings,
      clock: clock,
      ids: ids,
    );

    scheduler = PlatformQueueScheduler(
      policies: policies,
      queue: queue,
      router: router,
      clock: clock,
      host: hosts.scheduler,
    );
    gallery = PlatformGalleryService(
      ingestor: ingestor,
      scheduler: scheduler,
      images: images,
      host: hosts.gallery,
    );
    // The inbox hands the same capture over again until it is confirmed, so
    // a replayed copy has to be removed once the row is already there.
    capture = PlatformCaptureService(
      ingestor: ingestor,
      scheduler: scheduler,
      images: images,
      host: hosts.capture,
    );
    export = PlatformExportService(
      builder: ExportBuilder(
        memories: memories,
        conversations: conversations,
        vectors: database.vectors,
        clock: clock,
        embeddingModels: ExportBuilder.activeEmbeddingModel(router),
      ),
      images: images,
      cacheDirectory: exportCacheDirectory,
      clock: clock,
      files: hosts.files,
    );
    preferences = StoredAppPreferences(settings);
  }

  /// The database file inside the app files directory.
  static const databaseFile = 'memora.db';

  /// Where on-device model downloads land.
  static const modelsFolder = 'models';

  /// Opens the database in app storage and wires everything on top of it.
  ///
  /// Everything asynchronous happens here, so the constructor stays a plain
  /// list of what is built from what.
  static Future<MemoraAppServices> open({
    PlatformHosts? hosts,
    http.Client? httpClient,
    Clock clock = const SystemClock(),
    IdGenerator ids = const UuidGenerator(),
    Directory? exportCacheDirectory,
  }) async {
    final resolvedHosts = hosts ?? PlatformHosts();
    final filesDir = await resolvedHosts.files.filesDir();
    final database = MemoraDatabase.open(resolveInside(filesDir, databaseFile));
    try {
      return MemoraAppServices(
        database: database,
        filesDir: filesDir,
        httpClient: httpClient ?? http.Client(),
        hosts: resolvedHosts,
        clock: clock,
        ids: ids,
        exportCacheDirectory: exportCacheDirectory,
      );
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  /// The open database. Callers go through the stores; this is here so the
  /// composition root can close it.
  final MemoraDatabase database;

  /// Absolute path of the app files directory.
  final String filesDir;

  /// Shared by every network provider and by model downloads.
  final http.Client httpClient;

  final Clock clock;

  /// Downloaded on-device model files, behind [localModels].
  late final PlatformLocalModelFiles modelFiles;

  @override
  late final MemoryStore memories;
  @override
  late final QueueStore queue;
  @override
  late final ConversationStore conversations;
  @override
  late final SettingsStore settings;
  @override
  late final SecretStore secrets;
  @override
  late final ImageFiles images;
  @override
  late final ProviderRegistry providers;
  @override
  late final CapabilityRouter router;
  @override
  late final AiSettingsRepository aiSettings;
  @override
  late final MemoryIngestor ingestor;
  @override
  late final ProcessingPipeline pipeline;
  @override
  late final RetrievalEngine retrieval;
  @override
  late final ChatEngine chat;
  @override
  late final GalleryService gallery;
  @override
  late final CaptureService capture;
  @override
  late final QueueScheduler scheduler;
  @override
  late final LocalModelService localModels;
  @override
  late final LocalLlmModels localLlm;
  @override
  late final ExportService export;
  @override
  late final AppPreferences preferences;

  bool _disposed = false;

  /// Closes the database and releases the shared HTTP client. Nothing here
  /// can be used afterwards. Calling it again does nothing.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      // This also closes [httpClient], which every network provider and
      // every model download was handed.
      await modelFiles.close();
    } finally {
      database.close();
    }
  }
}
