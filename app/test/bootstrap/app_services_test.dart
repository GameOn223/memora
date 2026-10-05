/// The composition root over a real database, with the Android bridge faked.
///
/// Everything here runs on the host: the database is a real SQLite file in a
/// temporary directory, the core services and the provider registry are the
/// real ones, and only the generated host APIs are stubbed out, since those
/// need a phone.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:memora/src/bootstrap/app_preferences_impl.dart';
import 'package:memora/src/bootstrap/app_services_impl.dart';
import 'package:memora/src/platform/messages.g.dart';
import 'package:memora/src/platform/platform.dart';
import 'package:memora/src/services/app_services.dart';
import 'package:memora_core/memora_core.dart';
import 'package:memora_providers/memora_providers.dart';

/// A [FilesHostApi] that answers with a directory on this machine instead of
/// Android app storage.
class FakeFilesHost extends FilesHostApi {
  FakeFilesHost(this.directory);

  final String directory;

  @override
  Future<String> filesDir() async => directory;
}

/// Records that the shared client was released, and refuses to send. Nothing
/// in this test should reach the network.
class RecordingClient extends http.BaseClient {
  int closes = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw StateError('No test may call ${request.url}');

  @override
  void close() => closes++;
}

void main() {
  late Directory directory;
  late RecordingClient client;
  late MemoraAppServices services;

  Future<MemoraAppServices> openServices() => MemoraAppServices.open(
    hosts: PlatformHosts(files: FakeFilesHost(directory.path)),
    httpClient: client,
  );

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('memora_bootstrap_');
    client = RecordingClient();
    services = await openServices();
  });

  tearDown(() async {
    await services.dispose();
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // Leftovers in the system temp directory are harmless.
    }
  });

  // -------------------------------------------------------------------------
  // Opening
  // -------------------------------------------------------------------------

  test('opens one database file inside the app files directory', () async {
    final path = '${directory.path}/${MemoraAppServices.databaseFile}';
    expect(File(path).existsSync(), isTrue);
    expect(services.database.path, isNotNull);
    expect(services.filesDir, directory.path);
    // The schema is migrated on open, so the stores work right away.
    expect(services.database.schemaVersion, greaterThan(0));
    expect((await services.memories.storageStats()).memoryCount, 0);
  });

  test('images and models resolve under the files directory', () async {
    expect(
      services.images.absolutePath('originals/a.png'),
      resolveInside(directory.path, 'originals/a.png'),
    );
    expect(
      services.modelFiles.modelsDir,
      resolveInside(directory.path, MemoraAppServices.modelsFolder),
    );
    // Nothing outside app storage is reachable through a relative path.
    expect(
      () => services.images.absolutePath('../databases/other.db'),
      throwsArgumentError,
    );
  });

  // -------------------------------------------------------------------------
  // Members
  // -------------------------------------------------------------------------

  test('every member of AppServices is the real implementation', () {
    final AppServices app = services;

    expect(app.memories, same(services.database.memories));
    expect(app.queue, same(services.database.queue));
    expect(app.conversations, same(services.database.conversations));
    expect(app.settings, same(services.database.settings));
    expect(app.secrets, isA<PlatformSecretStore>());
    expect(app.images, isA<PlatformImageFiles>());

    expect(app.providers, isA<ProviderRegistry>());
    expect(app.router, isA<CapabilityRouter>());
    expect(app.aiSettings, isA<AiSettingsRepository>());

    expect(app.ingestor, isA<DefaultMemoryIngestor>());
    expect(app.pipeline, isA<DefaultProcessingPipeline>());
    expect(app.retrieval, isA<DefaultRetrievalEngine>());
    expect(app.chat, isA<AgentChatEngine>());

    expect(app.gallery, isA<PlatformGalleryService>());
    expect(app.capture, isA<PlatformCaptureService>());
    expect(app.scheduler, isA<PlatformQueueScheduler>());
    expect(app.localModels, isA<PlatformLocalModelService>());
    expect(app.export, isA<PlatformExportService>());
    expect(app.preferences, isA<StoredAppPreferences>());
  });

  test('ids are UUID v4, so two memories never collide', () {
    const ids = UuidGenerator();
    final first = ids.next();
    expect(first, isNot(ids.next()));
    expect(
      first,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
          r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  // -------------------------------------------------------------------------
  // Providers
  // -------------------------------------------------------------------------

  test('the shipped providers are registered, on-device first', () {
    expect(
      [for (final descriptor in services.providers.descriptors) descriptor.id],
      [
        'local',
        'openai',
        'groq',
        'nvidia',
        'openrouter',
        'ollama',
        'lmstudio',
        'custom',
        'gemini',
        'anthropic',
      ],
    );
    expect(
      [for (final d in builtInProviderDescriptors) d.id],
      [for (final d in services.providers.descriptors) d.id],
    );
  });

  test('the on-device provider runs on the platform adapters', () async {
    final local = await services.router.clientFor('local');
    expect(local, isA<LocalProviderClient>());
    expect(local.descriptor.location, ProviderLocation.onDevice);
    expect(local.vision(ocrRulesModelId), isA<OcrVisionService>());
    expect(local.embeddings('bge-small-en-v1.5'), isA<OnnxEmbeddingService>());
    expect(local.reranker(scoreFusionModelId), isA<FusionReranker>());
  });

  test('nothing is selected until the user chooses', () async {
    final statuses = await services.router.statuses();
    expect(statuses.keys, unorderedEquals(Capability.values));
    expect([
      for (final status in statuses.values) status.available,
    ], everyElement(isFalse));
    expect([
      for (final status in statuses.values) status.reason,
    ], everyElement(UnavailableReason.notConfigured));
    expect(await services.router.offDeviceProviders(), isEmpty);
    expect(await services.pipeline.currentBlock(), isA<NoVisionProvider>());
  });

  // -------------------------------------------------------------------------
  // Settings on the real store
  // -------------------------------------------------------------------------

  test('preferences and AI settings land in the settings table', () async {
    await services.preferences.setOnboardingComplete();
    await services.preferences.setTheme(ThemePreference.dark);
    await services.preferences.setGridColumns(4);
    await services.aiSettings.save(
      const AiSettings(
        selections: {
          Capability.vision: CapabilitySelection('local', ocrRulesModelId),
        },
        localOnly: true,
      ),
    );

    // Read through a second set of services over the same file, which is
    // what a restart does.
    final reopened = await openServices();
    addTearDown(reopened.dispose);
    expect(await reopened.preferences.onboardingComplete(), isTrue);
    expect(await reopened.preferences.theme(), ThemePreference.dark);
    expect(await reopened.preferences.gridColumns(), 4);
    final settings = await reopened.aiSettings.load();
    expect(settings.localOnly, isTrue);
    expect(
      settings.selections[Capability.vision],
      const CapabilitySelection('local', ocrRulesModelId),
    );
    // On-device vision is allowed in local-only mode, so the queue can run.
    expect(await reopened.pipeline.currentBlock(), isNull);
  });

  // -------------------------------------------------------------------------
  // Disposal
  // -------------------------------------------------------------------------

  test('disposal closes the database and the shared client', () async {
    await services.dispose();

    expect(client.closes, 1);
    expect(
      () => services.database.connection.select('SELECT 1'),
      throwsA(isA<StateError>()),
    );

    // Disposing again is harmless, which is what the tearDown relies on.
    await services.dispose();
    expect(client.closes, 1);
  });
}
