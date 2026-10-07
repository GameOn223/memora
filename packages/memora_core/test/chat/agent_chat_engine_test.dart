import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

import '../fakes/fake_stores.dart';

void main() {
  late FakeMemora db;
  late FakeImageFiles images;
  late FixedClock clock;
  final now = DateTime(2026, 9, 15, 10);

  setUp(() {
    clock = FixedClock(now);
    images = FakeImageFiles();
    db = FakeMemora()
      ..seed(
        id: 'jul',
        summary: 'Reliance electricity bill for July',
        category: 'utility_bill',
        takenAt: DateTime(2026, 7, 5),
        entities: [entity('Reliance')],
        attributes: [amount(1690)],
      )
      ..seed(
        id: 'aug',
        summary: 'Reliance electricity bill for August',
        category: 'utility_bill',
        takenAt: DateTime(2026, 8, 5),
        entities: [entity('Reliance')],
        attributes: [amount(2103)],
      )
      ..seed(
        id: 'sep',
        summary: 'Reliance electricity bill for September',
        category: 'utility_bill',
        takenAt: DateTime(2026, 9, 5),
        entities: [entity('Reliance')],
        attributes: [amount(1842)],
      );
  });

  Future<AgentChatEngine> engineWith(
    AiHarness ai, {
    int maxToolRounds = 6,
  }) async {
    return AgentChatEngine(
      conversations: db,
      router: ai.router,
      retrieval: DefaultRetrievalEngine(
        search: db,
        vectors: db,
        router: ai.router,
      ),
      search: db,
      vectors: db,
      memories: db,
      images: images,
      aiSettings: ai.aiSettings,
      clock: clock,
      ids: SequentialIds(),
      maxToolRounds: maxToolRounds,
    );
  }

  ToolCall call(String name, Map<String, Object?> args, {String id = 't1'}) =>
      ToolCall(id: id, name: name, arguments: args);

  Future<(List<ChatProgress>, Conversation)> ask(
    AgentChatEngine engine,
    String question, {
    String? conversationId,
    String? focusMemoryId,
  }) async {
    final conversation = conversationId == null
        ? await engine.startConversation(title: question)
        : (await db.getConversation(conversationId))!;
    final events = await engine
        .ask(conversation.id, question, focusMemoryId: focusMemoryId)
        .toList();
    return (events, conversation);
  }

  group('with a chat model', () {
    test('runs tools, cites sources and saves the answer', () async {
      final chat = ScriptedChatService([
        toolTurn([
          call('search_by_entity', {'value': 'Reliance'}),
        ]),
        answerTurn('Your August bill was ₹2,103 [[m:aug]].'),
      ]);
      final ai = await AiHarness.create(chat: chat);
      final engine = await engineWith(ai);

      final (events, conversation) = await ask(
        engine,
        'how much was my august bill?',
      );

      expect(events, hasLength(2));
      final used = events.first as ChatToolUsed;
      expect(used.entry.tool, 'search_by_entity');
      expect(used.entry.arguments, {'value': 'Reliance'});
      expect(used.entry.summary, '3 candidates');

      final message = (events.last as ChatAnswered).message;
      expect(message.content, 'Your August bill was ₹2,103.');
      expect(message.role, MessageRole.assistant);
      expect(message.provider, 'fake');
      expect(message.model, 'chat-model');
      expect(message.references.map((r) => r.memoryId), ['aug']);
      expect(message.references.single.position, 0);
      expect(message.references.single.relevance, isNotNull);
      expect(message.toolTrace.map((t) => t.tool), ['search_by_entity']);
      expect(message.presentation!.searchOnly, isFalse);
      expect(message.presentation!.headline, '₹2,103');
      expect(message.presentation!.sourceLabel, '1 memory · entity');

      final saved = await db.messages(conversation.id);
      expect(saved.map((m) => m.role), [
        MessageRole.user,
        MessageRole.assistant,
      ]);
      expect(saved.first.content, 'how much was my august bill?');

      final request = chat.requests.first;
      expect(request.system, contains('[[m:<memory id>]]'));
      expect(request.system, contains('15 September 2026'));
      expect(request.tools.map((t) => t.name), contains('search_memories'));
      expect((request.entries.single as UserEntry).text, contains('august'));

      final second = chat.requests[1];
      expect(second.entries, hasLength(3));
      expect((second.entries[1] as AssistantEntry).toolCalls, hasLength(1));
      final toolResult = second.entries[2] as ToolResultEntry;
      expect(toolResult.callId, 't1');
      expect(toolResult.toolName, 'search_by_entity');
      expect(toolResult.content, contains('"count":3'));
      expect(toolResult.isError, isFalse);
    });

    test('a general question is answered without searching', () async {
      final chat = ScriptedChatService([
        answerTurn('A kilowatt hour is a unit of energy, one kW for an hour.'),
      ]);
      final ai = await AiHarness.create(chat: chat);
      final engine = await engineWith(ai);

      final (events, conversation) = await ask(engine, 'what does kWh mean?');

      // No tool was used, and the model's own words survive intact.
      expect(events.whereType<ChatToolUsed>(), isEmpty);
      final message = (events.last as ChatAnswered).message;
      expect(
        message.content,
        'A kilowatt hour is a unit of energy, one kW for an hour.',
      );
      expect(message.references, isEmpty);
      expect(message.toolTrace, isEmpty);
      expect(
        message.presentation?.headline,
        isNull,
        reason: 'nothing was found, so there is no headline to show',
      );

      final saved = await db.messages(conversation.id);
      expect(saved.last.content, contains('kilowatt hour'));

      // The instructions have to tell it when each one applies.
      expect(chat.requests.single.system, contains('two things'));
      expect(chat.requests.single.system, contains('plainly general'));
    });

    test('a second search in the same turn becomes the active set', () async {
      final chat = ScriptedChatService([
        toolTurn([
          call('search_by_entity', {'value': 'Reliance'}),
        ]),
        toolTurn([
          call('search_by_attribute', {
            'type': 'amount',
            'min': 1800,
          }, id: 't2'),
        ]),
        toolTurn([
          call('aggregate_results', {'op': 'count'}, id: 't3'),
        ]),
        answerTurn('Two of them are over ₹1,800.'),
      ]);

      final (events, conversation) = await ask(
        await engineWith(await AiHarness.create(chat: chat)),
        'how many reliance bills are over 1800?',
      );

      final message = (events.last as ChatAnswered).message;
      expect(message.toolTrace.map((t) => t.summary), [
        '3 candidates',
        '2 candidates',
        '2',
      ]);
      final active = (await db.latestResultSet(conversation.id))!;
      expect(active.memoryIds, ['sep', 'aug']);

      final sets = db.resultSetRows
          .where((s) => s.conversationId == conversation.id)
          .toList();
      expect(sets, hasLength(2));
      expect(
        sets[1].createdAt.isAfter(sets[0].createdAt),
        isTrue,
        reason: 'a shared timestamp would leave the active set ambiguous',
      );
    });

    test('an aggregate answer is shown as a table', () async {
      final chat = ScriptedChatService([
        toolTurn([
          call('search_metadata', {
            'categories': ['utility_bill'],
          }),
        ]),
        toolTurn([
          call('aggregate_results', {'op': 'max'}, id: 't2'),
        ]),
        answerTurn('August was the highest at ₹2,103 [[m:aug]].'),
      ]);
      final ai = await AiHarness.create(chat: chat);

      final (events, _) = await ask(
        await engineWith(ai),
        'which one was highest?',
      );

      final message = (events.last as ChatAnswered).message;
      final presentation = message.presentation!;
      expect(presentation.layout, SourceLayout.table);
      expect(presentation.tableAttribute, 'amount');
      expect(presentation.headline, '₹2,103');
      expect(presentation.highlightMemoryId, 'aug');
      expect(message.toolTrace.map((t) => t.summary), [
        '3 candidates',
        '₹2,103',
      ]);
      expect(events.whereType<ChatToolUsed>(), hasLength(2));
    });

    test('the headline is the memory total, not a line item', () async {
      db.seed(
        id: 'store',
        summary: 'Nature Basket receipt',
        category: 'receipt',
        takenAt: DateTime(2026, 9, 11),
        attributes: [
          amount(100, label: 'subtotal'),
          amount(42, label: 'tax'),
          amount(842),
        ],
      );
      final chat = ScriptedChatService([
        answerTurn('It came to ₹842 [[m:store]].'),
      ]);

      final (events, _) = await ask(
        await engineWith(await AiHarness.create(chat: chat)),
        'how much was the nature basket receipt?',
      );

      final presentation = (events.last as ChatAnswered).message.presentation!;
      expect(presentation.headline, '₹842');
    });

    test('drops citations that name no memory', () async {
      final chat = ScriptedChatService([
        answerTurn('Maybe this one [[m:ghost]] or this [[m:aug]].'),
      ]);

      final (events, _) = await ask(
        await engineWith(await AiHarness.create(chat: chat)),
        'anything about bills?',
      );

      final message = (events.last as ChatAnswered).message;
      expect(message.references.map((r) => r.memoryId), ['aug']);
      expect(message.content, 'Maybe this one or this.');
    });

    test('a tool error goes back to the model', () async {
      final chat = ScriptedChatService([
        toolTurn([
          call('search_memories', {'amount_min': 'lots'}),
        ]),
        answerTurn('I could not work that out.'),
      ]);

      final (events, _) = await ask(
        await engineWith(await AiHarness.create(chat: chat)),
        'bills over lots',
      );

      final result = chat.requests[1].entries.last as ToolResultEntry;
      expect(result.isError, isTrue);
      expect(result.content, contains('amount_min must be a number'));
      expect((events.last as ChatAnswered).message.content, isNotEmpty);
    });

    test('stops after the round limit with an honest answer', () async {
      final chat = ScriptedChatService([
        for (var i = 0; i < 4; i++)
          toolTurn([
            call('search_by_entity', {'value': 'Reliance'}, id: 't$i'),
          ]),
      ]);
      final ai = await AiHarness.create(chat: chat);

      final (events, _) = await ask(
        await engineWith(ai, maxToolRounds: 2),
        'what did i spend?',
      );

      final message = (events.last as ChatAnswered).message;
      expect(message.content, contains('closest matches'));
      expect(message.toolTrace, hasLength(2));
      expect(message.references, isNotEmpty);
      expect(chat.requests, hasLength(3));
    });

    test('provider failures keep the question and report why', () async {
      final chat = ScriptedChatService([
        const AiTransientException('Upstream timeout'),
      ]);
      final ai = await AiHarness.create(chat: chat);

      final (events, conversation) = await ask(
        await engineWith(ai),
        'anything about bills?',
      );

      final failure = events.single as ChatFailed;
      // What went wrong, not just that something did: "did not respond" is
      // equally true of a timed-out server and a model that failed to load.
      expect(failure.message, 'Fake AI: Upstream timeout');
      expect(failure.retryable, isTrue);
      final saved = await db.messages(conversation.id);
      expect(saved.map((m) => m.role), [MessageRole.user]);
    });

    test('a failure with nothing to say still asks for a retry', () async {
      final chat = ScriptedChatService([const AiTransientException('')]);

      final (events, _) = await ask(
        await engineWith(await AiHarness.create(chat: chat)),
        'anything about bills?',
      );

      expect(
        (events.single as ChatFailed).message,
        'Fake AI did not respond. Try again.',
      );
    });

    test('a store failure while saving keeps the question', () async {
      final chat = ScriptedChatService([answerTurn('Here you go.')]);
      final engine = await engineWith(await AiHarness.create(chat: chat));
      final conversation = await engine.startConversation(title: 'Bills');
      db.failAssistantMessages = true;

      final events = await engine.ask(conversation.id, 'anything?').toList();

      expect(events.single, isA<ChatFailed>());
      db.failAssistantMessages = false;
      expect((await db.messages(conversation.id)).map((m) => m.role), [
        MessageRole.user,
      ]);
    });

    test('a configuration failure is not retryable', () async {
      final chat = ScriptedChatService([
        const AiConfigurationException('key rejected'),
      ]);

      final (events, _) = await ask(
        await engineWith(await AiHarness.create(chat: chat)),
        'hello',
      );

      final failure = events.single as ChatFailed;
      expect(failure.retryable, isFalse);
      // The reason the provider gave, not a template about API keys. For a
      // model on the phone that advice was no help at all, and it buried
      // what the runtime said.
      expect(failure.message, contains('key rejected'));
      expect(failure.message, contains('Fake AI'));
    });

    test('a configuration failure with nothing to say still advises', () async {
      final chat = ScriptedChatService([const AiConfigurationException('')]);

      final (events, _) = await ask(
        await engineWith(await AiHarness.create(chat: chat)),
        'hello',
      );

      expect((events.single as ChatFailed).message, contains('settings'));
    });
  });

  group('verification', () {
    Future<ChatMessage> answerWithVision(
      List<Object> verifyScript, {
      bool verifyAnswers = true,
    }) async {
      final vision = ScriptedVisionService(verify: verifyScript);
      final chat = ScriptedChatService([
        toolTurn([
          call('search_metadata', {
            'categories': ['utility_bill'],
          }),
        ]),
        toolTurn([
          call('aggregate_results', {'op': 'max'}, id: 't2'),
        ]),
        answerTurn('August was the highest at ₹2,103 [[m:aug]].'),
      ]);
      final ai = await AiHarness.create(chat: chat, vision: vision);
      await ai.update((s) => s.copyWith(verifyAnswers: verifyAnswers));

      final (events, _) = await ask(
        await engineWith(ai),
        'which bill was highest?',
      );
      return (events.last as ChatAnswered).message;
    }

    test('confirms a headline against the original image', () async {
      final message = await answerWithVision([
        const VerificationResult(confirmed: true),
      ]);

      expect(message.presentation!.verification, VerificationState.verified);
      expect(
        message.presentation!.headlineNote,
        'Verified against the original image',
      );
      expect(message.content, 'August was the highest at ₹2,103.');
    });

    test('corrects a headline when the image shows something else', () async {
      final message = await answerWithVision([
        const VerificationResult(confirmed: false, observedValue: '₹2,130'),
      ]);

      expect(message.presentation!.verification, VerificationState.corrected);
      expect(message.presentation!.headline, '₹2,130');
      expect(message.content, contains('₹2,130'));
    });

    test('a rambling observed value is not spliced in', () async {
      final message = await answerWithVision([
        const VerificationResult(
          confirmed: false,
          observedValue:
              'I am not able to tell from this image, but the total near '
              'the bottom might be ₹2,130 or maybe ₹2,180.',
        ),
      ]);

      expect(message.presentation!.verification, VerificationState.none);
      expect(message.presentation!.headline, '₹2,103');
      expect(message.content, 'August was the highest at ₹2,103.');
    });

    test('a failed check leaves the answer as it was', () async {
      final message = await answerWithVision([
        const AiTransientException('vision down'),
      ]);

      expect(message.presentation!.verification, VerificationState.none);
      expect(message.presentation!.headline, '₹2,103');
    });

    test('nothing is sent when verification is off', () async {
      final message = await answerWithVision([
        const VerificationResult(confirmed: true),
      ], verifyAnswers: false);

      expect(message.presentation!.verification, VerificationState.none);
      expect(message.presentation!.headlineNote, isNull);
    });
  });

  group('when a model cannot call tools', () {
    test('answers from search and keeps the model on the message', () async {
      final chat = ScriptedChatService([
        const ToolCallingUnavailableException(
          providerId: 'local',
          modelId: 'gemma-3-1b-it-int4',
        ),
      ]);
      final engine = await engineWith(await AiHarness.create(chat: chat));

      final (events, conversation) = await ask(engine, 'reliance bills');

      final message = (events.last as ChatAnswered).message;
      expect(
        message.content,
        'Found 3 memories matching reliance, utility bills or invoices.',
      );
      expect(message.presentation!.searchOnly, isTrue);
      expect(message.provider, 'fake');
      expect(message.model, 'chat-model');
      expect(message.references.map((r) => r.memoryId).toSet(), {
        'jul',
        'aug',
        'sep',
      });
      expect(await db.latestResultSet(conversation.id), isNotNull);
      expect(chat.requests, hasLength(1));
    });

    test('a failure worth retrying is still a failure', () async {
      final engine = await engineWith(
        await AiHarness.create(
          chat: ScriptedChatService([
            const AiTransientException('busy', providerId: 'local'),
          ]),
        ),
      );

      final (events, _) = await ask(engine, 'reliance bills');

      expect(events.last, isA<ChatFailed>());
    });
  });

  group('without a chat model', () {
    test('answers from search and marks the message search-only', () async {
      final ai = await AiHarness.create();
      final engine = await engineWith(ai);

      final (events, conversation) = await ask(engine, 'reliance bills');

      final message = (events.last as ChatAnswered).message;
      expect(
        message.content,
        'Found 3 memories matching reliance, utility bills or invoices.',
      );
      expect(message.presentation!.searchOnly, isTrue);
      expect(message.provider, isNull);
      expect(message.references.map((r) => r.memoryId).toSet(), {
        'jul',
        'aug',
        'sep',
      });
      expect(events.whereType<ChatToolUsed>(), hasLength(1));
      expect(await db.latestResultSet(conversation.id), isNotNull);
    });

    test('a follow-up works on the memories found last time', () async {
      final ai = await AiHarness.create();
      final engine = await engineWith(ai);

      final (_, conversation) = await ask(engine, 'reliance bills');
      final events = await engine
          .ask(conversation.id, 'which one was highest?')
          .toList();

      final message = (events.last as ChatAnswered).message;
      expect(
        message.content,
        'Found 3 memories. The highest amount is ₹2,103 (Aug 2026).',
      );
      expect(message.presentation!.highlightMemoryId, 'aug');
    });

    test('a question with its own filters searches fresh', () async {
      db.seed(
        id: 'groceries',
        summary: 'Grocery receipt from Nature Basket',
        category: 'receipt',
        takenAt: DateTime(2026, 9, 12),
        attributes: [amount(842)],
      );
      final engine = await engineWith(await AiHarness.create());

      final (_, conversation) = await ask(engine, 'reliance bills');
      final events = await engine
          .ask(conversation.id, 'how many receipts do i have?')
          .toList();

      final message = (events.last as ChatAnswered).message;
      expect(message.content, 'Found 1 memory matching receipts.');
      expect(message.references.single.memoryId, 'groceries');
    });

    test('a question that points back stays on the last results', () async {
      db.seed(
        id: 'mac',
        summary: 'MacBook Air price comparison',
        category: 'comparison',
        takenAt: DateTime(2026, 9, 12),
        attributes: [amount(124900)],
      );
      final engine = await engineWith(await AiHarness.create());

      final (_, conversation) = await ask(engine, 'reliance bills');
      final events = await engine
          .ask(conversation.id, 'of those, how many are over ₹1,800?')
          .toList();

      final message = (events.last as ChatAnswered).message;
      expect(message.content, 'Found 2 memories matching over ₹1,800.');
      expect(message.references.map((r) => r.memoryId), ['sep', 'aug']);
    });

    test('a focused question only looks at that memory', () async {
      final ai = await AiHarness.create();
      final engine = await engineWith(ai);

      final (events, _) = await ask(
        engine,
        'what is this?',
        focusMemoryId: 'jul',
      );

      final message = (events.last as ChatAnswered).message;
      expect(message.references.map((r) => r.memoryId), ['jul']);
    });
  });

  test('availability reports the chat model or search only', () async {
    final withModel = await engineWith(
      await AiHarness.create(chat: ScriptedChatService([])),
    );
    final availability = await withModel.availability();
    expect(availability.searchOnly, isFalse);
    expect(availability.providerName, 'Fake AI');
    expect(availability.modelId, 'chat-model');

    final without = await engineWith(await AiHarness.create());
    expect((await without.availability()).searchOnly, isTrue);
  });

  test('conversations are titled from the first question', () async {
    final engine = await engineWith(await AiHarness.create());

    final untitled = await engine.startConversation();
    expect(untitled.title, 'New conversation');

    final long = await engine.startConversation(
      title: 'show me every single reliance electricity bill from last year',
    );
    expect(long.title.length, lessThanOrEqualTo(48));
    expect(long.title, startsWith('show me every single reliance'));
  });
}
