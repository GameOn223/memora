/// Local fakes and fixtures for the end-to-end test.
///
/// The unit test fakes in `packages/memora_core/test/fakes` are not
/// importable from another package, so the pieces the pipeline needs are
/// written again here, small and scripted. Everything else in the walk is
/// the real code: a real SQLite database, the real core services and a real
/// provider registry behind a real capability router.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memora_core/memora_core.dart';
import 'package:memora_database/memora_database.dart';

// ---------------------------------------------------------------------------
// Platform ports
// ---------------------------------------------------------------------------

/// A clock the test moves by hand, so stored timestamps are predictable.
class TestClock implements Clock {
  TestClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;

  void advance(Duration by) => current = current.add(by);
}

/// Ids with a readable prefix, so a failure says which generator made a value.
class SequentialIds implements IdGenerator {
  SequentialIds(this.prefix);

  final String prefix;
  int _next = 0;

  @override
  String next() => '$prefix-${++_next}';
}

/// [ImageFiles] over a real directory. Thumbnails are copies of the source,
/// which is enough for a test that never decodes an image.
class TempImageFiles implements ImageFiles {
  TempImageFiles(this.root);

  final String root;

  /// Source paths [createThumbnail] was asked for, in order.
  final List<String> thumbnailRequests = [];

  /// Paths handed to [delete], including ones that were already gone.
  final List<String> deleteRequests = [];

  final List<String> reads = [];

  @override
  String absolutePath(String relativePath) => '$root/$relativePath';

  @override
  Future<Uint8List> readBytes(String relativePath) async {
    reads.add(relativePath);
    return File(absolutePath(relativePath)).readAsBytes();
  }

  @override
  Future<String> createThumbnail(String sourcePath, {int maxEdge = 512}) async {
    thumbnailRequests.add(sourcePath);
    final name = sourcePath.split('/').last.split('.').first;
    final thumbnailPath = 'thumbnails/$name.webp';
    write(thumbnailPath, File(absolutePath(sourcePath)).readAsBytesSync());
    return thumbnailPath;
  }

  @override
  Future<void> delete(List<String> relativePaths) async {
    deleteRequests.addAll(relativePaths);
    for (final path in relativePaths) {
      final file = File(absolutePath(path));
      if (file.existsSync()) file.deleteSync();
    }
  }

  void write(String relativePath, List<int> bytes) {
    final file = File(absolutePath(relativePath))
      ..parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }

  bool exists(String relativePath) =>
      File(absolutePath(relativePath)).existsSync();
}

class InMemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<List<String>> keys() async => values.keys.toList();
}

// ---------------------------------------------------------------------------
// Scripted AI services
// ---------------------------------------------------------------------------

/// Vision that answers with the understanding JSON written for each fixture,
/// parsed the same way a real adapter parses a model response.
class ScriptedVisionService implements VisionService {
  ScriptedVisionService(this.fixtures);

  final List<ImageFixture> fixtures;
  final List<VisionRequest> analyzeRequests = [];
  final List<VerificationRequest> verifyRequests = [];

  @override
  Future<MemoryUnderstanding> analyze(VisionRequest request) async {
    analyzeRequests.add(request);
    final fixture = _forPath(request.absoluteImagePath);
    if (fixture == null) {
      throw AiContentException(
        'No scripted understanding for ${request.absoluteImagePath}',
      );
    }
    final json = jsonDecode(fixture.understandingJson) as Map<String, Object?>;
    return MemoryUnderstanding.fromJson(json);
  }

  /// Confirms a figure only when it matches what the fixture says the image
  /// really shows, so a wrong stored value would be caught.
  @override
  Future<VerificationResult> verify(VerificationRequest request) async {
    verifyRequests.add(request);
    final shown = _forPath(request.absoluteImagePath)?.amountOnImage;
    return VerificationResult(
      confirmed: shown != null && shown == request.expectedValue,
      observedValue: shown,
    );
  }

  ImageFixture? _forPath(String? absolutePath) {
    if (absolutePath == null) return null;
    final name = absolutePath.split('/').last;
    for (final fixture in fixtures) {
      if (fixture.fileName == name) return fixture;
    }
    return null;
  }
}

/// Chat that replays turns the test pushes onto [script].
class ScriptedChatService implements ChatService {
  final List<ChatTurn> script = [];
  final List<ChatRequest> requests = [];

  @override
  Future<ChatTurn> complete(ChatRequest request) async {
    requests.add(request);
    if (script.isEmpty) {
      throw StateError('No scripted chat turn left for ${request.entries}');
    }
    return script.removeAt(0);
  }
}

ChatTurn toolTurn(List<ToolCall> calls) =>
    ChatTurn(text: '', toolCalls: calls, stopReason: ChatStopReason.toolUse);

ChatTurn answerTurn(String text) => ChatTurn(
  text: text,
  toolCalls: const [],
  stopReason: ChatStopReason.endTurn,
);

/// Embeddings the test controls completely.
///
/// Every text lands on one axis of a tiny space, chosen by the first keyword
/// that appears in it. Two texts on the same axis have cosine similarity 1,
/// and texts on different axes have 0, so a query can be made to find a
/// memory whose words it does not share.
class AxisEmbeddingService implements EmbeddingService {
  AxisEmbeddingService(this.axes);

  /// Keyword to axis index. The first entry whose keyword appears in the
  /// lowercased text wins. Anything unmatched lands on the last axis.
  final Map<String, int> axes;

  static const dimensions = 8;

  final List<List<String>> calls = [];
  final List<EmbeddingPurpose> purposes = [];

  @override
  EmbeddingModelInfo get model => const EmbeddingModelInfo(
    provider: 'scripted',
    modelId: 'bge-small-en-v1.5',
    version: '1',
    dimensions: dimensions,
  );

  @override
  Future<List<Float32List>> embed(
    List<String> texts, {
    EmbeddingPurpose purpose = EmbeddingPurpose.document,
  }) async {
    calls.add(texts);
    purposes.add(purpose);
    return [for (final text in texts) vectorFor(text)];
  }

  Float32List vectorFor(String text) {
    final lower = text.toLowerCase();
    var axis = dimensions - 1;
    for (final entry in axes.entries) {
      if (lower.contains(entry.key)) {
        axis = entry.value;
        break;
      }
    }
    return Float32List(dimensions)..[axis] = 1;
  }
}

// ---------------------------------------------------------------------------
// Provider registration
// ---------------------------------------------------------------------------

/// The one provider this test registers. It hands out whichever scripted
/// service the harness holds.
class ScriptedProviderClient implements ProviderClient {
  ScriptedProviderClient({
    required this.descriptor,
    required this._vision,
    required this._chat,
    required this._embeddings,
  });

  @override
  final ProviderDescriptor descriptor;

  final VisionService _vision;
  final ChatService _chat;
  final EmbeddingService _embeddings;

  @override
  VisionService? vision(String modelId) => _vision;

  @override
  ChatService? chat(String modelId) => _chat;

  @override
  EmbeddingService? embeddings(String modelId) => _embeddings;

  /// The provider offers no reranking, so retrieval falls back to the
  /// on-device fusion reranker, as it does on a phone with none selected.
  @override
  RerankService? reranker(String modelId) => null;

  @override
  Future<List<String>> listModels(Capability capability) async => const [];

  @override
  Future<ConnectionCheck> testConnection() async => const ConnectionCheck.ok();
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// One image on disk, the JSON its vision model returns, and the figure the
/// image really shows.
class ImageFixture {
  ImageFixture({
    required this.imagePath,
    required this.sha256,
    required this.takenAt,
    required this.understandingJson,
    this.amountOnImage,
    this.byteSize = 240000,
  });

  /// Relative to the app files directory, as the platform layer writes it.
  final String imagePath;

  /// The digest the platform layer computed while copying the file.
  final String sha256;
  final DateTime takenAt;
  final String understandingJson;

  /// What the amount on the image reads as, used by answer verification.
  final String? amountOnImage;
  final int byteSize;

  String get fileName => imagePath.split('/').last;

  ImportedFile get imported => ImportedFile(
    imagePath: imagePath,
    sha256: sha256,
    mimeType: 'image/png',
    width: 1080,
    height: 2400,
    byteSize: byteSize,
    takenAt: takenAt,
  );

  /// Bytes written to disk. Two fixtures with the same digest get the same
  /// bytes, the way two copies of one screenshot would.
  List<int> get bytes => utf8.encode('memora-fixture:$sha256');
}

/// The Reliance electricity bill for August, with a due date and an amount.
final augustBill = ImageFixture(
  imagePath: 'originals/reliance-august.png',
  sha256: 'sha256-reliance-august',
  takenAt: DateTime(2026, 8, 5, 9, 30),
  amountOnImage: '₹1,842',
  understandingJson: '''
{
  "summary": "Reliance electricity bill for August 2026",
  "category": "utility_bill",
  "visual_description": "A utility bill open in a payments app.",
  "extracted_text": "Reliance Energy\\nConsumer 900218847\\nBilling period 01 Aug 2026 to 31 Aug 2026\\nAmount due Rs 1,842\\nDue date 31/08/2026",
  "keywords": ["reliance", "electricity", "bill", "august"],
  "entities": [{"type": "company", "value": "Reliance Energy"}],
  "dates": [{"type": "due_date", "value": "2026-08-31"}],
  "amounts": [{"type": "total", "value": 1842, "currency": "INR"}],
  "attributes": [{"type": "account_number", "value": ".... 4471"}],
  "confidence": 0.86
}
''',
);

/// The September bill. Its supply address is the only place the word
/// "Dahisar" appears anywhere in the library.
final septemberBill = ImageFixture(
  imagePath: 'originals/reliance-september.png',
  sha256: 'sha256-reliance-september',
  takenAt: DateTime(2026, 9, 4, 8, 15),
  amountOnImage: '₹2,103',
  understandingJson: '''
{
  "summary": "Reliance electricity bill for September 2026",
  "category": "utility_bill",
  "visual_description": "A utility bill open in a payments app.",
  "extracted_text": "Reliance Energy\\nSupply address Dahisar West\\nBilling period 01 Sep 2026 to 30 Sep 2026\\nAmount due Rs 2,103\\nDue date 30/09/2026",
  "keywords": ["reliance", "electricity", "bill", "september"],
  "entities": [{"type": "company", "value": "Reliance Energy"}],
  "dates": [{"type": "due_date", "value": "2026-09-30"}],
  "amounts": [{"type": "total", "value": 2103, "currency": "INR"}],
  "attributes": [{"type": "account_number", "value": ".... 4471"}],
  "confidence": 0.9
}
''',
);

/// A laptop comparison. It carries amounts well over the bill filter, so only
/// the entity filter keeps it out of the bills answer.
final laptopComparison = ImageFixture(
  imagePath: 'originals/laptop-comparison.png',
  sha256: 'sha256-laptop-comparison',
  takenAt: DateTime(2026, 8, 12, 21, 5),
  understandingJson: '''
{
  "summary": "Laptop comparison between the ThinkPad X1 Carbon and the MacBook Air",
  "category": "comparison",
  "visual_description": "A side by side specification table on a shopping site.",
  "extracted_text": "ThinkPad X1 Carbon Gen 12 Rs 1,24,900\\nMacBook Air M4 Rs 99,900\\nWeight 1.09 kg vs 1.24 kg",
  "keywords": ["laptop", "comparison", "thinkpad", "macbook"],
  "entities": [
    {"type": "product", "value": "ThinkPad X1 Carbon"},
    {"type": "product", "value": "MacBook Air"}
  ],
  "dates": [],
  "amounts": [
    {"type": "price", "value": 124900, "currency": "INR"},
    {"type": "price", "value": 99900, "currency": "INR"}
  ],
  "attributes": [],
  "confidence": 0.74
}
''',
);

/// A flight booking with a PNR. It shares no word with the question the
/// semantic search asks, and it is not the newest memory, so a hit for it can
/// only have come from the vectors.
final flightBooking = ImageFixture(
  imagePath: 'originals/flight-booking.png',
  sha256: 'sha256-flight-booking',
  takenAt: DateTime(2026, 8, 20, 19, 40),
  amountOnImage: '₹5,480',
  understandingJson: '''
{
  "summary": "IndiGo flight booking from Mumbai to Delhi",
  "category": "booking",
  "visual_description": "A booking confirmation open in an email app.",
  "extracted_text": "IndiGo 6E 5031\\nMumbai BOM to Delhi DEL\\n24 Sep 2026 06:40\\nPNR K7X9QW\\nTotal paid Rs 5,480",
  "keywords": ["indigo", "flight", "booking", "mumbai", "delhi"],
  "entities": [{"type": "company", "value": "IndiGo"}],
  "dates": [{"type": "departure_date", "value": "2026-09-24"}],
  "amounts": [{"type": "total", "value": 5480, "currency": "INR"}],
  "attributes": [{"type": "pnr", "value": "K7X9QW"}],
  "confidence": 0.81
}
''',
);

/// A second copy of the August bill, as the picker would hand it over again.
/// Same digest, different file.
final augustBillCopy = ImageFixture(
  imagePath: 'originals/reliance-august-copy.png',
  sha256: augustBill.sha256,
  takenAt: augustBill.takenAt,
  understandingJson: augustBill.understandingJson,
);

final imageFixtures = [
  augustBill,
  septemberBill,
  laptopComparison,
  flightBooking,
];

// ---------------------------------------------------------------------------
// The wiring under test
// ---------------------------------------------------------------------------

/// The real stack: a SQLite database in memory, the real core services and
/// one scripted provider behind a real router.
class MemoraHarness {
  MemoraHarness._({
    required this.db,
    required this.images,
    required this.clock,
    required this.registry,
    required this.router,
    required this.aiSettings,
    required this.secrets,
    required this.vision,
    required this.chat,
    required this.embeddings,
    required this.descriptor,
  });

  static const providerId = 'scripted';
  static const visionModel = 'scripted-vision';
  static const chatModel = 'scripted-chat';
  static const embeddingModel = 'bge-small-en-v1.5';

  /// Where each fixture's embedding text and the queries that should find it
  /// land. Keyed on a word that appears in one group of texts only.
  static const embeddingAxes = {
    'indigo': 0,
    'airport': 0,
    'reliance': 1,
    'thinkpad': 2,
    'laptop': 2,
  };

  final MemoraDatabase db;
  final TempImageFiles images;
  final TestClock clock;
  final ProviderRegistry registry;
  final CapabilityRouter router;
  final AiSettingsRepository aiSettings;
  final InMemorySecretStore secrets;
  final ScriptedVisionService vision;
  final ScriptedChatService chat;
  final AxisEmbeddingService embeddings;
  final ProviderDescriptor descriptor;

  final SequentialIds memoryIds = SequentialIds('mem');
  final SequentialIds chatIds = SequentialIds('chat');

  /// Ids of the imported memories, in fixture order, filled by [importAll].
  final List<String> importedIds = [];

  String get augustId => importedIds[0];

  String get septemberId => importedIds[1];

  String get laptopId => importedIds[2];

  String get flightId => importedIds[3];

  late final MemoryIngestor ingestor = DefaultMemoryIngestor(
    memories: db.memories,
    images: images,
    clock: clock,
    ids: memoryIds,
  );

  late final ProcessingPipeline pipeline = DefaultProcessingPipeline(
    queue: db.queue,
    memories: db.memories,
    vectors: db.vectors,
    router: router,
    images: images,
    policy: QueuePolicyRepository(db.settings),
    clock: clock,
  );

  late final RetrievalEngine retrieval = DefaultRetrievalEngine(
    search: db.search,
    vectors: db.vectors,
    router: router,
  );

  late final ChatEngine chatEngine = AgentChatEngine(
    conversations: db.conversations,
    router: router,
    retrieval: retrieval,
    search: db.search,
    vectors: db.vectors,
    memories: db.memories,
    images: images,
    aiSettings: aiSettings,
    clock: clock,
    ids: chatIds,
  );

  late final ExportBuilder export = ExportBuilder(
    memories: db.memories,
    conversations: db.conversations,
    vectors: db.vectors,
    clock: clock,
    embeddingModels: ExportBuilder.activeEmbeddingModel(router),
  );

  static Future<MemoraHarness> create() async {
    final directory = Directory.systemTemp.createTempSync('memora_e2e_');
    addTearDown(() {
      try {
        directory.deleteSync(recursive: true);
      } on FileSystemException {
        // Leftovers in the system temp directory are harmless.
      }
    });

    final db = MemoraDatabase.openInMemory();
    addTearDown(db.close);

    final images = TempImageFiles(directory.path.replaceAll(r'\', '/'));
    final vision = ScriptedVisionService([...imageFixtures, augustBillCopy]);
    final chat = ScriptedChatService();
    final embeddings = AxisEmbeddingService(embeddingAxes);
    final descriptor = ProviderDescriptor(
      id: providerId,
      displayName: 'Scripted AI',
      location: ProviderLocation.onDevice,
      capabilities: const {
        Capability.vision,
        Capability.chat,
        Capability.embeddings,
      },
    );

    final registry = ProviderRegistry()
      ..register(
        descriptor,
        (config) => ScriptedProviderClient(
          descriptor: descriptor,
          vision: vision,
          chat: chat,
          embeddings: embeddings,
        ),
      );
    final aiSettings = AiSettingsRepository(db.settings);
    final secrets = InMemorySecretStore();
    await aiSettings.save(
      const AiSettings(
        selections: {
          Capability.vision: CapabilitySelection(providerId, visionModel),
          Capability.chat: CapabilitySelection(providerId, chatModel),
          Capability.embeddings: CapabilitySelection(
            providerId,
            embeddingModel,
          ),
        },
      ),
    );

    return MemoraHarness._(
      db: db,
      images: images,
      clock: TestClock(DateTime(2026, 9, 21, 22, 10)),
      registry: registry,
      router: CapabilityRouter(
        registry: registry,
        settings: aiSettings,
        secrets: secrets,
      ),
      aiSettings: aiSettings,
      secrets: secrets,
      vision: vision,
      chat: chat,
      embeddings: embeddings,
      descriptor: descriptor,
    );
  }

  /// Writes the fixture files and runs them through the ingestor, with a
  /// second copy of the August bill at the end of the batch.
  Future<IngestReport> importAll() async {
    final files = [...imageFixtures, augustBillCopy];
    for (final fixture in files) {
      images.write(fixture.imagePath, fixture.bytes);
    }
    final report = await ingestor.ingest([
      for (final fixture in files) fixture.imported,
    ], MemorySource.gallery);
    importedIds
      ..clear()
      ..addAll(report.addedIds);
    return report;
  }

  Future<QueueRunReport> processAll() =>
      pipeline.runQueue(budget: const Duration(minutes: 5), processNow: true);

  Future<void> importAndProcess() async {
    await importAll();
    await processAll();
  }

  /// Clears the chat selection, leaving Ask with search alone.
  Future<void> removeChatModel() async {
    final settings = await aiSettings.load();
    await aiSettings.save(settings.withoutSelection(Capability.chat));
  }

  /// Rows in a table that belong to one memory.
  int countFor(String table, String memoryId) =>
      db.connection.select(
            'SELECT COUNT(*) AS n FROM $table WHERE memory_id = ?',
            [memoryId],
          ).first['n']
          as int;

  /// Whether the full-text index still holds a row for this memory.
  bool hasFtsRow(int seq) =>
      (db.connection.select(
            'SELECT COUNT(*) AS n FROM memories_fts WHERE rowid = ?',
            [seq],
          ).first['n']
          as int) >
      0;

  int seqOf(String memoryId) =>
      db.connection.select('SELECT seq FROM memories WHERE id = ?', [
            memoryId,
          ]).first['seq']
          as int;
}

/// Runs [ChatEngine.ask] to completion and returns everything it emitted.
Future<List<ChatProgress>> ask(
  ChatEngine engine,
  String conversationId,
  String question,
) => engine.ask(conversationId, question).toList();

/// The answer from a finished ask.
ChatMessage answerFrom(List<ChatProgress> events) {
  for (final event in events) {
    if (event is ChatAnswered) return event.message;
    if (event is ChatFailed) fail('Ask failed: ${event.message}');
  }
  fail('Ask emitted no answer: $events');
}
