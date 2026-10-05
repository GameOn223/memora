import 'package:memora_core/memora_core.dart';
import 'package:memora_database/memora_database.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  late MemoraDatabase db;
  late ConversationStore conversations;
  final now = DateTime.utc(2026, 9, 15, 20);

  setUp(() {
    db = openTestDatabase();
    conversations = db.conversations;
  });

  DateTime at(int minutes) => now.add(Duration(minutes: minutes));

  ChatMessage message(
    String id,
    String conversationId,
    DateTime createdAt, {
    MessageRole role = MessageRole.user,
    String content = 'Show me my Reliance bills',
    List<MessageReference> references = const [],
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      role: role,
      content: content,
      createdAt: createdAt,
      references: references,
    );
  }

  group('conversations', () {
    test('create, get and list newest updated first', () async {
      final first = await conversations.createConversation('c1', 'Bills', now);
      expect(first.id, 'c1');
      expect(first.title, 'Bills');
      expect(first.createdAt, now);
      expect(first.updatedAt, now);

      await conversations.createConversation('c2', 'Flights', at(1));
      await conversations.createConversation('c3', 'Laptops', at(2));

      final loaded = (await conversations.getConversation('c2'))!;
      expect(loaded.title, 'Flights');
      expect(loaded.createdAt, at(1));
      expect(loaded.updatedAt, at(1));
      expect(await conversations.getConversation('missing'), isNull);

      expect((await conversations.listConversations()).map((c) => c.id), [
        'c3',
        'c2',
        'c1',
      ]);
    });

    test('adding a message moves a conversation to the top', () async {
      await conversations.createConversation('c1', 'Bills', now);
      await conversations.createConversation('c2', 'Flights', at(1));

      await conversations.addMessage(message('m1', 'c1', at(5)));

      expect((await conversations.listConversations()).map((c) => c.id), [
        'c1',
        'c2',
      ]);
      expect((await conversations.getConversation('c1'))!.updatedAt, at(5));
    });

    test('an older message does not move updated time back', () async {
      await conversations.createConversation('c1', 'Bills', at(10));
      await conversations.addMessage(message('m1', 'c1', at(3)));
      expect((await conversations.getConversation('c1'))!.updatedAt, at(10));
    });

    test('a new conversation is not pinned', () async {
      final created = await conversations.createConversation(
        'c1',
        'Bills',
        now,
      );
      expect(created.pinned, isFalse);
      expect((await conversations.getConversation('c1'))!.pinned, isFalse);
    });

    test('renaming changes the title and leaves the order alone', () async {
      await conversations.createConversation('c1', 'Bills', now);
      await conversations.createConversation('c2', 'Flights', at(1));

      await conversations.renameConversation('c1', 'Electricity bills', at(99));

      final renamed = (await conversations.getConversation('c1'))!;
      expect(renamed.title, 'Electricity bills');
      expect(renamed.updatedAt, now);
      expect((await conversations.listConversations()).map((c) => c.id), [
        'c2',
        'c1',
      ]);

      await conversations.renameConversation('missing', 'Nowhere', at(99));
    });

    test('pinned conversations list first, newest updated in each', () async {
      await conversations.createConversation('c1', 'Bills', now);
      await conversations.createConversation('c2', 'Flights', at(1));
      await conversations.createConversation('c3', 'Laptops', at(2));

      await conversations.setConversationPinned('c1', true, at(99));

      expect((await conversations.listConversations()).map((c) => c.id), [
        'c1',
        'c3',
        'c2',
      ]);
      final pinned = (await conversations.getConversation('c1'))!;
      expect(pinned.pinned, isTrue);
      expect(pinned.updatedAt, now);

      await conversations.setConversationPinned('c2', true, at(99));
      expect((await conversations.listConversations()).map((c) => c.id), [
        'c2',
        'c1',
        'c3',
      ]);

      await conversations.setConversationPinned('c2', false, at(99));
      expect((await conversations.listConversations()).map((c) => c.id), [
        'c1',
        'c3',
        'c2',
      ]);

      await conversations.setConversationPinned('missing', true, at(99));
    });

    test('a pinned conversation stays pinned when a message arrives', () async {
      await conversations.createConversation('c1', 'Bills', now);
      await conversations.setConversationPinned('c1', true, at(1));

      await conversations.addMessage(message('m1', 'c1', at(5)));

      final loaded = (await conversations.getConversation('c1'))!;
      expect(loaded.pinned, isTrue);
      expect(loaded.updatedAt, at(5));
    });
  });

  group('messages', () {
    late String reliance;
    late String airtel;

    setUp(() async {
      reliance = await seedMemory(db);
      airtel = await seedMemory(db);
      await conversations.createConversation('c1', 'Bills', now);
    });

    test('round-trip content, metadata, presentation and trace', () async {
      await conversations.addMessage(message('m1', 'c1', at(1)));
      await conversations.addMessage(
        ChatMessage(
          id: 'm2',
          conversationId: 'c1',
          role: MessageRole.assistant,
          content: 'The highest was ₹2,103 in August.',
          createdAt: at(2),
          provider: 'groq',
          model: 'llama-3.3-70b-versatile',
          presentation: MessagePresentation(
            layout: SourceLayout.table,
            headline: '₹2,103',
            headlineNote: 'Verified against the original image',
            tableAttribute: 'amount',
            highlightMemoryId: airtel,
            sourceLabel: '2 memories · entity + semantic',
            verification: VerificationState.verified,
          ),
          toolTrace: const [
            ToolTraceEntry(
              tool: 'search_by_entity',
              arguments: {'value': 'Reliance', 'limit': 20},
              summary: '8 candidates',
            ),
            ToolTraceEntry(
              tool: 'aggregate_results',
              arguments: {'op': 'max', 'attribute': 'amount'},
              summary: '₹2,103',
            ),
          ],
          references: [
            MessageReference(memoryId: airtel, position: 1),
            MessageReference(memoryId: reliance, position: 0, relevance: 0.92),
          ],
        ),
      );

      final loaded = await conversations.messages('c1');
      expect(loaded.map((m) => m.id), ['m1', 'm2']);

      final question = loaded.first;
      expect(question.role, MessageRole.user);
      expect(question.content, 'Show me my Reliance bills');
      expect(question.createdAt, at(1));
      expect(question.conversationId, 'c1');
      expect(question.presentation, isNull);
      expect(question.toolTrace, isEmpty);
      expect(question.references, isEmpty);
      expect(question.provider, isNull);
      expect(question.model, isNull);

      final answer = loaded.last;
      expect(answer.role, MessageRole.assistant);
      expect(answer.content, 'The highest was ₹2,103 in August.');
      expect(answer.provider, 'groq');
      expect(answer.model, 'llama-3.3-70b-versatile');

      final presentation = answer.presentation!;
      expect(presentation.layout, SourceLayout.table);
      expect(presentation.headline, '₹2,103');
      expect(presentation.headlineNote, 'Verified against the original image');
      expect(presentation.tableAttribute, 'amount');
      expect(presentation.highlightMemoryId, airtel);
      expect(presentation.sourceLabel, '2 memories · entity + semantic');
      expect(presentation.verification, VerificationState.verified);
      expect(presentation.searchOnly, isFalse);

      expect(answer.toolTrace.map((t) => t.display), [
        'search_by_entity(value: "Reliance", limit: 20) · 8 candidates',
        'aggregate_results(op: "max", attribute: "amount") · ₹2,103',
      ]);

      expect(answer.references.map((r) => r.memoryId), [reliance, airtel]);
      expect(answer.references.map((r) => r.position), [0, 1]);
      expect(answer.references.first.relevance, closeTo(0.92, 1e-9));
      expect(answer.references.last.relevance, isNull);
    });

    test('keep created order and stay within their conversation', () async {
      await conversations.createConversation('c2', 'Other', now);
      await conversations.addMessage(message('late', 'c1', at(9)));
      await conversations.addMessage(message('early', 'c1', at(1)));
      await conversations.addMessage(message('same-a', 'c1', at(5)));
      await conversations.addMessage(message('same-b', 'c1', at(5)));
      await conversations.addMessage(message('elsewhere', 'c2', at(2)));

      expect((await conversations.messages('c1')).map((m) => m.id), [
        'early',
        'same-a',
        'same-b',
        'late',
      ]);
      expect(await conversations.messages('missing'), isEmpty);
    });

    test('skip references to memories that do not exist', () async {
      await conversations.addMessage(
        message(
          'm1',
          'c1',
          at(1),
          role: MessageRole.assistant,
          references: [
            const MessageReference(memoryId: 'gone', position: 0),
            MessageReference(memoryId: reliance, position: 1),
            MessageReference(memoryId: reliance, position: 2),
          ],
        ),
      );

      final refs = (await conversations.messages('c1')).single.references;
      expect(refs.map((r) => r.memoryId), [reliance]);
    });

    test('lose references to a memory once it is deleted', () async {
      await conversations.addMessage(
        message(
          'm1',
          'c1',
          at(1),
          role: MessageRole.assistant,
          references: [
            MessageReference(memoryId: reliance, position: 0),
            MessageReference(memoryId: airtel, position: 1),
          ],
        ),
      );

      await db.memories.deleteMemory(reliance);

      final loaded = (await conversations.messages('c1')).single;
      expect(loaded.references.map((r) => r.memoryId), [airtel]);
    });

    test('conversationsCiting counts distinct conversations', () async {
      await conversations.createConversation('c2', 'More bills', now);
      MessageReference cite(String id) =>
          MessageReference(memoryId: id, position: 0);
      await conversations.addMessage(
        message('a', 'c1', at(1), references: [cite(reliance)]),
      );
      await conversations.addMessage(
        message('b', 'c1', at(2), references: [cite(reliance)]),
      );
      await conversations.addMessage(
        message('c', 'c2', at(3), references: [cite(reliance), cite(airtel)]),
      );

      expect(await conversations.conversationsCiting(reliance), 2);
      expect(await conversations.conversationsCiting(airtel), 1);
      expect(await conversations.conversationsCiting('nothing'), 0);
    });
  });

  group('result sets', () {
    setUp(() async {
      await conversations.createConversation('c1', 'Bills', now);
      await conversations.createConversation('c2', 'Flights', now);
    });

    test('save and load with ids in order', () async {
      await conversations.saveResultSet(
        ResultSet(
          id: 'r1',
          conversationId: 'c1',
          messageId: 'm7',
          description: 'category=utility_bill, entity=Reliance',
          memoryIds: const ['z', 'a', 'm'],
          createdAt: at(1),
        ),
      );

      final loaded = (await conversations.getResultSet('r1'))!;
      expect(loaded.id, 'r1');
      expect(loaded.conversationId, 'c1');
      expect(loaded.messageId, 'm7');
      expect(loaded.description, 'category=utility_bill, entity=Reliance');
      expect(loaded.memoryIds, ['z', 'a', 'm']);
      expect(loaded.createdAt, at(1));
      expect(
        scalar(db, "SELECT memory_ids FROM result_sets WHERE id = 'r1'"),
        '["z","a","m"]',
      );
      expect(await conversations.getResultSet('missing'), isNull);
    });

    test('latest is the newest in that conversation', () async {
      ResultSet set(String id, String conversation, DateTime createdAt) =>
          ResultSet(
            id: id,
            conversationId: conversation,
            description: id,
            memoryIds: [id],
            createdAt: createdAt,
          );
      await conversations.saveResultSet(set('old', 'c1', at(1)));
      await conversations.saveResultSet(set('new', 'c1', at(5)));
      await conversations.saveResultSet(set('backdated', 'c1', at(2)));
      await conversations.saveResultSet(set('other', 'c2', at(9)));

      final latest = (await conversations.latestResultSet('c1'))!;
      expect(latest.id, 'new');
      expect(latest.messageId, isNull);
      expect(latest.memoryIds, ['new']);

      await conversations.saveResultSet(set('tie', 'c1', at(5)));
      expect((await conversations.latestResultSet('c1'))!.id, 'tie');
      expect(await conversations.latestResultSet('missing'), isNull);
    });

    test('saving the same id again replaces it', () async {
      await conversations.saveResultSet(
        ResultSet(
          id: 'r1',
          conversationId: 'c1',
          description: 'first',
          memoryIds: const ['a'],
          createdAt: at(1),
        ),
      );
      await conversations.saveResultSet(
        ResultSet(
          id: 'r1',
          conversationId: 'c1',
          messageId: 'm1',
          description: 'narrowed',
          memoryIds: const ['b', 'a'],
          createdAt: at(2),
        ),
      );

      final loaded = (await conversations.getResultSet('r1'))!;
      expect(loaded.description, 'narrowed');
      expect(loaded.memoryIds, ['b', 'a']);
      expect(loaded.messageId, 'm1');
      expect(scalar(db, 'SELECT COUNT(*) FROM result_sets'), 1);
    });
  });

  group('deleteConversation', () {
    test('removes messages, references and result sets', () async {
      final memory = await seedMemory(db);
      await conversations.createConversation('c1', 'Bills', now);
      await conversations.createConversation('c2', 'Keep', now);
      for (final conversation in ['c1', 'c2']) {
        await conversations.addMessage(
          message(
            '$conversation-m',
            conversation,
            at(1),
            references: [MessageReference(memoryId: memory, position: 0)],
          ),
        );
        await conversations.saveResultSet(
          ResultSet(
            id: '$conversation-r',
            conversationId: conversation,
            description: 'all',
            memoryIds: [memory],
            createdAt: at(1),
          ),
        );
      }

      await conversations.deleteConversation('c1');

      expect(await conversations.getConversation('c1'), isNull);
      expect(await conversations.messages('c1'), isEmpty);
      expect(await conversations.getResultSet('c1-r'), isNull);
      expect(
        scalar(
          db,
          "SELECT COUNT(*) FROM message_references WHERE message_id = 'c1-m'",
        ),
        0,
      );
      expect(
        (await conversations.messages('c2')).single.references,
        hasLength(1),
      );
      expect(await conversations.getResultSet('c2-r'), isNotNull);
      expect(await conversations.conversationsCiting(memory), 1);
      expect(await db.memories.getMemory(memory), isNotNull);

      await conversations.deleteConversation('missing');
    });
  });
}
