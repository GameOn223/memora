import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

import '../fakes/fake_stores.dart';

void main() {
  late FakeMemora db;
  late ExportBuilder builder;
  final clock = FixedClock(DateTime.utc(2026, 9, 15, 4, 30));
  final model = FakeEmbeddingService().model;

  setUp(() async {
    db = FakeMemora()
      ..seed(
        id: 'jul',
        summary: 'Reliance electricity bill for July',
        category: 'utility_bill',
        visualDescription: 'A utility bill in a mobile app.',
        extractedText: 'Amount due Rs 1,690',
        takenAt: DateTime.utc(2026, 7, 5, 9),
        addedAt: DateTime.utc(2026, 7, 6, 10),
        entities: [entity('Reliance')],
        attributes: [amount(1690), dateAttribute('due_date', '2026-07-31')],
        keywords: ['reliance', 'electricity'],
        thumbnailPath: 'thumbnails/jul.webp',
        processedAt: DateTime.utc(2026, 7, 6, 10, 1),
      )
      ..seed(
        id: 'goa',
        summary: 'IndiGo flight to Goa',
        category: 'booking',
        takenAt: DateTime.utc(2026, 9, 10, 7),
        imagePath: 'originals/goa.jpg',
        mimeType: 'image/jpeg',
      );
    await db.addProcessingRecord(
      ProcessingRecord(
        memoryId: 'jul',
        capability: Capability.vision,
        provider: 'nvidia',
        model: 'meta/llama-3.2-11b-vision-instruct',
        outcome: ProcessingOutcome.succeeded,
        latency: const Duration(milliseconds: 1840),
        createdAt: DateTime.utc(2026, 7, 6, 10, 1),
      ),
    );
    await db.upsert(
      'jul',
      FakeEmbeddingService.vectorFor('bill', model.dimensions),
      model,
      DateTime.utc(2026, 7, 6),
    );

    await db.createConversation('c1', 'Bills', DateTime.utc(2026, 9, 14));
    await db.addMessage(
      ChatMessage(
        id: 'm1',
        conversationId: 'c1',
        role: MessageRole.user,
        content: 'how much was the july bill?',
        createdAt: DateTime.utc(2026, 9, 14, 12),
      ),
    );
    await db.addMessage(
      ChatMessage(
        id: 'm2',
        conversationId: 'c1',
        role: MessageRole.assistant,
        content: 'It was ₹1,690.',
        createdAt: DateTime.utc(2026, 9, 14, 12, 0, 5),
        references: const [
          MessageReference(memoryId: 'jul', position: 0, relevance: 1),
        ],
        toolTrace: const [
          ToolTraceEntry(
            tool: 'search_by_entity',
            arguments: {'value': 'Reliance'},
            summary: '1 candidate',
          ),
        ],
        presentation: const MessagePresentation(headline: '₹1,690'),
        provider: 'groq',
        model: 'llama-3.3-70b-versatile',
      ),
    );
    await db.saveResultSet(
      ResultSet(
        id: 'r1',
        conversationId: 'c1',
        messageId: 'm2',
        description: 'entity=Reliance',
        memoryIds: const ['jul'],
        createdAt: DateTime.utc(2026, 9, 14, 12),
      ),
    );

    builder = ExportBuilder(
      memories: db,
      conversations: db,
      vectors: db,
      clock: clock,
      appVersion: '0.1.0',
      embeddingModels: () async => [model],
    );
  });

  test('the manifest names the format and counts what is inside', () async {
    expect((await builder.manifest()).toJson(), {
      'format': 'memora-export',
      'format_version': 1,
      'exported_at': '2026-09-15T04:30:00.000Z',
      'app_version': '0.1.0',
      'counts': {'memories': 2, 'conversations': 1, 'images': 2},
    });
  });

  test(
    'memories stream oldest first with everything derived from them',
    () async {
      final records = await builder.memories().toList();

      expect(records.map((r) => r.memory.id), ['jul', 'goa']);
      expect(records.first.sourcePath, 'originals/jul.png');
      expect(records.first.toJson(), {
        'id': 'jul',
        'image_file': 'images/jul.png',
        'source_path': 'originals/jul.png',
        'thumbnail_path': 'thumbnails/jul.webp',
        'source': 'gallery',
        'sha256': 'sha-jul',
        'mime_type': 'image/png',
        'width': 1080,
        'height': 2400,
        'byte_size': 1000,
        'taken_at': '2026-07-05T09:00:00.000Z',
        'added_at': '2026-07-06T10:00:00.000Z',
        'updated_at': '2026-07-06T10:00:00.000Z',
        'processed_at': '2026-07-06T10:01:00.000Z',
        'status': 'ready',
        'attempts': 0,
        'summary': 'Reliance electricity bill for July',
        'category': 'utility_bill',
        'visual_description': 'A utility bill in a mobile app.',
        'extracted_text': 'Amount due Rs 1,690',
        'entities': [
          {
            'type': 'company',
            'value': 'Reliance',
            'normalized_value': 'reliance',
          },
        ],
        'attributes': [
          {
            'type': 'amount',
            'value': '₹1,690',
            'value_num': 1690,
            'currency': 'INR',
            'label': 'total',
          },
          {
            'type': 'due_date',
            'value': '31 Jul 2026',
            'value_date': '2026-07-31',
          },
        ],
        'keywords': ['reliance', 'electricity'],
        'processing': [
          {
            'capability': 'vision',
            'provider': 'nvidia',
            'model': 'meta/llama-3.2-11b-vision-instruct',
            'status': 'succeeded',
            'latency_ms': 1840,
            'created_at': '2026-07-06T10:01:00.000Z',
          },
        ],
        'embeddings': [
          {'model_id': 'fake/bag-of-words', 'version': '1', 'dimensions': 64},
        ],
      });
    },
  );

  test('a memory with no vector exports no embedding metadata', () async {
    final records = await builder.memories().toList();
    expect(records.last.toJson()['embeddings'], isEmpty);
    expect(records.last.toJson()['image_file'], 'images/goa.jpg');
  });

  test('vectors themselves never leave', () async {
    final json = (await builder.memories().toList()).first.toJson();
    expect(json.toString(), isNot(contains('vector')));
  });

  test('conversations carry messages, sources and the active set', () async {
    final conversations = await builder.conversations().toList();

    expect(conversations.single, {
      'id': 'c1',
      'title': 'Bills',
      'created_at': '2026-09-14T00:00:00.000Z',
      'updated_at': '2026-09-14T12:00:05.000Z',
      'messages': [
        {
          'id': 'm1',
          'role': 'user',
          'content': 'how much was the july bill?',
          'created_at': '2026-09-14T12:00:00.000Z',
        },
        {
          'id': 'm2',
          'role': 'assistant',
          'content': 'It was ₹1,690.',
          'created_at': '2026-09-14T12:00:05.000Z',
          'provider': 'groq',
          'model': 'llama-3.3-70b-versatile',
          'presentation': {
            'layout': 'strip',
            'headline': '₹1,690',
            'verification': 'none',
            'search_only': false,
          },
          'tool_trace': [
            {
              'tool': 'search_by_entity',
              'arguments': {'value': 'Reliance'},
              'summary': '1 candidate',
            },
          ],
          'references': [
            {'memory_id': 'jul', 'position': 0, 'relevance': 1.0},
          ],
        },
      ],
      'active_result_set': {
        'id': 'r1',
        'message_id': 'm2',
        'description': 'entity=Reliance',
        'memory_ids': ['jul'],
        'created_at': '2026-09-14T12:00:00.000Z',
      },
    });
  });

  test('works when there is no embedding model at all', () async {
    final plain = ExportBuilder(
      memories: db,
      conversations: db,
      vectors: db,
      clock: clock,
      embeddingModels: ExportBuilder.noEmbeddingModels,
    );
    final records = await plain.memories().toList();
    expect(records, hasLength(2));
    expect(records.first.toJson()['embeddings'], isEmpty);
  });
}
