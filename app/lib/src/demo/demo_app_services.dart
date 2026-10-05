import 'dart:async';
import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

import '../bootstrap/app_preferences_impl.dart';
import '../services/app_services.dart';
import 'demo_ai.dart';
import 'demo_chat.dart';
import 'demo_data.dart';
import 'demo_images.dart';
import 'demo_stores.dart';

/// In-memory [AppServices] filled with the design's sample data. Used by
/// widget tests, screenshot tests and demo builds until the real services
/// are wired in.
class DemoAppServices implements AppServices {
  DemoAppServices({
    Clock? clock,
    bool seed = true,
    bool onboardingComplete = true,
    GalleryAccess galleryAccess = GalleryAccess.full,
    int galleryImageCount = 12,
    Duration chatStep = const Duration(milliseconds: 350),
  }) : clock = clock ?? const SystemClock() {
    db = DemoDatabase(this.clock);
    renderer = DemoImageRenderer();
    memories = DemoMemoryStore(db);
    queue = DemoQueueStore(db);
    conversations = DemoConversationStore(db);
    images = DemoImageFiles(db, renderer);
    providers = buildDemoRegistry();
    aiSettings = AiSettingsRepository(settings);
    router = CapabilityRouter(
      registry: providers,
      settings: aiSettings,
      secrets: secrets,
    );
    chat = DemoChatEngine(
      db: db,
      conversations: conversations,
      router: router,
      step: chatStep,
    );
    scheduler = DemoQueueScheduler(db, queue);
    gallery = DemoGalleryService(
      db: db,
      renderer: renderer,
      scheduler: scheduler,
      access: galleryAccess,
      imageCount: galleryImageCount,
    );
    pipeline = DemoPipeline(db, router, settings);
    // The same preferences the real services use, over the demo's settings
    // store, so a demo build reads and writes them exactly as a phone does.
    preferences = StoredAppPreferences(settings);
    if (onboardingComplete) {
      settings.values[StoredAppPreferences.onboardingKey] = true;
    }
    ingestor = DemoIngestor(memories, clock: this.clock);
    retrieval = DemoRetrieval(db);
    if (seed) {
      db.seedMemories();
      unawaited(chat.seed());
      settings.values[AiSettingsRepository.key] = const AiSettings(
        selections: {
          Capability.vision: CapabilitySelection('nvidia', 'nemotron-vl-3b'),
          Capability.chat: CapabilitySelection('groq', 'llama-3.3-70b'),
          Capability.embeddings: CapabilitySelection(
            'local',
            'bge-small-en-v1.5',
          ),
          Capability.reranking: CapabilitySelection('local', 'score-fusion'),
        },
        acknowledgedCloudProviders: {'nvidia', 'groq'},
      ).toJson();
      secrets.values
        ..[CapabilityRouter.apiKeyName('nvidia')] = 'nvapi-Hk29dXz0pLq7Q2f'
        ..[CapabilityRouter.apiKeyName('groq')] = 'gsk_Tn4mW81rVx91b';
    }
  }

  final Clock clock;
  late final DemoDatabase db;
  late final DemoImageRenderer renderer;

  @override
  late final DemoMemoryStore memories;
  @override
  late final DemoQueueStore queue;
  @override
  late final DemoConversationStore conversations;
  @override
  final DemoSettingsStore settings = DemoSettingsStore();
  @override
  final DemoSecretStore secrets = DemoSecretStore();
  @override
  late final DemoImageFiles images;
  @override
  late final ProviderRegistry providers;
  @override
  late final CapabilityRouter router;
  @override
  late final AiSettingsRepository aiSettings;
  @override
  late final DemoIngestor ingestor;
  @override
  late final DemoPipeline pipeline;
  @override
  late final DemoRetrieval retrieval;
  @override
  late final DemoChatEngine chat;
  @override
  late final DemoGalleryService gallery;
  @override
  final DemoCaptureService capture = DemoCaptureService();
  @override
  late final DemoQueueScheduler scheduler;
  @override
  final DemoLocalModelService localModels = DemoLocalModelService();
  @override
  final DemoExportService export = DemoExportService();
  @override
  late final AppPreferences preferences;
}

class DemoGalleryService implements GalleryService {
  DemoGalleryService({
    required this.db,
    required this.renderer,
    required this.scheduler,
    required GalleryAccess access,
    required int imageCount,
  }) : accessState = access {
    for (var i = 0; i < imageCount; i++) {
      final spec = i < demoGallerySpecs.length
          ? demoGallerySpecs[i]
          : DemoGallerySpec(
              4 + (i - demoGallerySpecs.length) ~/ 6,
              '12:00',
              DemoImageKind.values[i % DemoImageKind.values.length],
              i,
            );
      final uri = 'content://media/external/images/media/${1000 + i}';
      final taken = db
          .at(spec.daysAgo, spec.time)
          .subtract(Duration(seconds: i));
      _kinds[uri] = (spec.kind, spec.seed);
      _images.add(
        DeviceImage(
          uri: uri,
          takenAt: taken,
          width: 1080,
          height: 2400,
          byteSize: 380 * 1024 + i * 1000,
          mimeType: 'image/png',
        ),
      );
    }
    _images.sort((a, b) => b.takenAt.compareTo(a.takenAt));
  }

  final DemoDatabase db;
  final DemoImageRenderer renderer;
  final DemoQueueScheduler scheduler;
  GalleryAccess accessState;

  /// What [requestAccess] grants.
  GalleryAccess grantOnRequest = GalleryAccess.full;

  /// What the system picker returns.
  List<String>? pickerResult;

  /// When set, the next listing or add throws.
  bool failNext = false;

  final List<DeviceImage> _images = [];
  final Map<String, (DemoImageKind, int)> _kinds = {};
  final Set<String> _added = {};

  /// Every call to [list] as `(offset, limit)`.
  final List<(int, int)> listCalls = [];

  /// Every batch passed to [addToMemora].
  final List<List<String>> addCalls = [];
  int openSettingsCalls = 0;

  List<DeviceImage> get images => List.unmodifiable(_images);

  @override
  Future<GalleryAccess> access() async => accessState;

  @override
  Future<GalleryAccess> requestAccess() async => accessState = grantOnRequest;

  @override
  Future<void> openAppSettings() async => openSettingsCalls++;

  @override
  Future<DeviceImagePage> list({
    required int offset,
    required int limit,
  }) async {
    listCalls.add((offset, limit));
    if (failNext) {
      failNext = false;
      throw StateError('The gallery could not be read');
    }
    final page = _images.skip(offset).take(limit).toList();
    return DeviceImagePage(
      images: page,
      hasMore: offset + page.length < _images.length,
    );
  }

  @override
  Future<Uint8List> thumbnail(String uri, {int size = 256}) {
    final kind = _kinds[uri];
    if (kind == null) return Future.value(Uint8List(0));
    return renderer.render(kind.$1, seed: kind.$2);
  }

  @override
  Future<List<String>> pickWithSystemPicker({int maxItems = 100}) async =>
      pickerResult ?? [for (final i in _images.take(2)) i.uri];

  @override
  Future<AddImagesResult> addToMemora(List<String> uris) async {
    addCalls.add([...uris]);
    if (failNext) {
      failNext = false;
      throw StateError('The images could not be copied');
    }
    var added = 0;
    var duplicates = 0;
    final now = db.clock.now();
    for (final uri in uris) {
      if (!_added.add(uri)) {
        duplicates++;
        continue;
      }
      final image = _images.where((i) => i.uri == uri).firstOrNull;
      final id = db.nextId('g');
      final kind = _kinds[uri] ?? (DemoImageKind.chat, 0);
      db.images['originals/$id.png'] = kind;
      db.images['thumbnails/$id.webp'] = kind;
      db.memories[id] = Memory(
        id: id,
        imagePath: 'originals/$id.png',
        thumbnailPath: 'thumbnails/$id.webp',
        source: MemorySource.gallery,
        sha256: 'sha-$uri',
        mimeType: image?.mimeType ?? 'image/png',
        width: image?.width ?? 1080,
        height: image?.height ?? 2400,
        byteSize: image?.byteSize ?? 400000,
        takenAt: image?.takenAt ?? now,
        addedAt: now,
        updatedAt: now,
        status: ProcessingStatus.captured,
      );
      added++;
    }
    db.touch();
    await scheduler.refresh();
    return AddImagesResult(added: added, duplicates: duplicates, failed: 0);
  }
}

class DemoCaptureService implements CaptureService {
  bool accessibilitySupported = true;
  bool accessibilityEnabled = false;
  bool canRequestTile = true;
  bool notificationsAllowed = false;
  int tileRequests = 0;
  int accessibilitySettingsOpened = 0;

  @override
  Future<CaptureSetup> setup() async => CaptureSetup(
    accessibilitySupported: accessibilitySupported,
    accessibilityEnabled: accessibilityEnabled,
    canRequestTile: canRequestTile,
    notificationsAllowed: notificationsAllowed,
  );

  @override
  Future<void> openAccessibilitySettings() async {
    accessibilitySettingsOpened++;
  }

  @override
  Future<bool> requestAddTile() async {
    tileRequests++;
    return true;
  }

  @override
  Future<bool> requestNotificationPermission() async =>
      notificationsAllowed = true;

  @override
  Future<int> ingestInbox() async => 0;
}

class DemoQueueScheduler implements QueueScheduler {
  DemoQueueScheduler(this.db, this.queue);

  final DemoDatabase db;
  final DemoQueueStore queue;
  QueuePolicy current = const QueuePolicy();
  int processNowCalls = 0;
  int refreshCalls = 0;

  @override
  Future<QueuePolicy> policy() async => current;

  @override
  Future<void> setPolicy(QueuePolicy policy) async {
    current = policy;
    db.touch();
  }

  /// Finishes the item in progress and starts the next one, so the demo
  /// visibly moves.
  @override
  Future<void> processNow() async {
    processNowCalls++;
    final now = db.clock.now();
    for (final m in db.memories.values.toList()) {
      if (m.status == ProcessingStatus.processing) {
        await queue.markReady(m.id, now);
      }
    }
    await queue.claimNext(now, const Duration(minutes: 10));
  }

  @override
  Future<void> refresh() async => refreshCalls++;
}

class DemoLocalModelService implements LocalModelService {
  DemoLocalModelService({this.tick = const Duration(milliseconds: 120)});

  final Duration tick;
  final _controller = StreamController<List<LocalModelInfo>>.broadcast();
  List<LocalModelInfo> _models = const [
    LocalModelInfo(
      id: 'bge-small-en-v1.5',
      displayName: 'bge-small-en v1.5',
      sizeBytes: 34245934,
      state: LocalModelState.notDownloaded,
    ),
  ];
  final List<String> downloads = [];

  /// When set, the next download throws part way through.
  bool failNext = false;

  void _emit(List<LocalModelInfo> models) {
    _models = models;
    _controller.add(models);
  }

  LocalModelInfo _with(LocalModelInfo m, LocalModelState state, [double? p]) =>
      LocalModelInfo(
        id: m.id,
        displayName: m.displayName,
        sizeBytes: m.sizeBytes,
        state: state,
        progress: p,
      );

  @override
  Stream<List<LocalModelInfo>> watch() async* {
    yield _models;
    yield* _controller.stream;
  }

  @override
  Future<void> download(String modelId) async {
    downloads.add(modelId);
    if (failNext) {
      failNext = false;
      throw StateError('The download could not be verified');
    }
    for (var step = 1; step <= 10; step++) {
      _emit([
        for (final m in _models)
          m.id == modelId
              ? _with(m, LocalModelState.downloading, step / 10)
              : m,
      ]);
      await Future<void>.delayed(tick);
    }
    _emit([
      for (final m in _models)
        m.id == modelId ? _with(m, LocalModelState.ready) : m,
    ]);
  }

  @override
  Future<void> remove(String modelId) async {
    _emit([
      for (final m in _models)
        m.id == modelId ? _with(m, LocalModelState.notDownloaded) : m,
    ]);
  }
}

class DemoExportService implements ExportService {
  int exports = 0;

  /// When set, the next export throws, so error paths can be tested.
  bool failNext = false;

  @override
  Future<bool> exportAll({
    void Function(ExportProgress progress)? onProgress,
  }) async {
    exports++;
    if (failNext) {
      failNext = false;
      throw StateError('The export could not be written');
    }
    const total = 17;
    for (var i = 1; i <= total; i++) {
      await Future<void>.delayed(Duration.zero);
      onProgress?.call(ExportProgress(done: i, total: total));
    }
    return true;
  }
}

class DemoPipeline implements ProcessingPipeline {
  DemoPipeline(this.db, this.router, SettingsStore settings)
    : policy = QueuePolicyRepository(settings);

  final DemoDatabase db;
  final CapabilityRouter router;

  /// Where a rate limit the queue is waiting out is kept, so the demo answers
  /// `currentBlock` the same way a phone does.
  final QueuePolicyRepository policy;
  int reindexCalls = 0;

  /// When set, the next reindex throws.
  bool failNext = false;

  @override
  Future<QueueBlock?> currentBlock() async {
    final limit = await policy.loadRateLimit(db.clock.now());
    if (limit != null) return limit.block;
    try {
      await router.vision();
      return null;
    } on CapabilityUnavailableException catch (e) {
      // The real mapping, so demo and phone never drift apart.
      return DefaultProcessingPipeline.blockFor(e);
    }
  }

  @override
  Future<ProcessOutcome> processNext() async => const QueueEmpty();

  @override
  Future<QueueRunReport> runQueue({
    required Duration budget,
    bool processNow = false,
  }) async => const QueueRunReport(processed: 0, remaining: false);

  @override
  Future<int> reindexEmbeddings({required Duration budget}) async {
    reindexCalls++;
    if (failNext) {
      failNext = false;
      throw StateError('The embedding model is not loaded');
    }
    return db.memories.values
        .where((m) => m.status == ProcessingStatus.ready)
        .length;
  }
}

class DemoIngestor implements MemoryIngestor {
  DemoIngestor(this.memories, {required this.clock});

  final MemoryStore memories;
  final Clock clock;
  int _next = 0;

  @override
  Future<IngestReport> ingest(
    List<ImportedFile> files,
    MemorySource source,
  ) async {
    final outcome = await memories.insertCaptured([
      for (final f in files)
        NewMemory(
          id: 'ingest-${_next++}',
          imagePath: f.imagePath,
          source: source,
          sha256: f.sha256,
          mimeType: f.mimeType,
          width: f.width,
          height: f.height,
          byteSize: f.byteSize,
          takenAt: f.takenAt,
        ),
    ], clock.now());
    return IngestReport(
      addedIds: outcome.insertedIds,
      duplicateCount: outcome.duplicates.length,
    );
  }

  @override
  Future<int> backfillThumbnails() async => 0;
}

class DemoRetrieval implements RetrievalEngine {
  DemoRetrieval(this.db);

  final DemoDatabase db;

  @override
  Future<RetrievalResult> search(RetrievalQuery query) async {
    final text = (query.text ?? '').toLowerCase();
    final hits = [
      for (final m in db.memories.values)
        if (text.isEmpty || (m.summary ?? '').toLowerCase().contains(text))
          RankedMemory(
            card: MemoryCard(
              id: m.id,
              takenAt: m.takenAt,
              status: m.status,
              summary: m.summary,
              category: m.category,
              thumbnailPath: m.thumbnailPath,
            ),
            score: 1,
            foundBy: const {RetrievalStrategy.text},
          ),
    ];
    return RetrievalResult(
      hits: hits.take(query.effectiveLimit).toList(),
      strategiesUsed: const {RetrievalStrategy.text},
    );
  }
}
