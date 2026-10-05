/// The whole product path over the real stack: a real SQLite database, the
/// real core services and scripted AI providers behind a real router.
///
/// Nothing here is faked except the three AI capabilities and the file system
/// the images live on. If two packages disagree at a boundary, this is where
/// it shows.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:memora_core/memora_core.dart';

import '_support.dart';

const question = 'Which Reliance bill was the highest?';

void main() {
  late MemoraHarness harness;

  setUp(() async {
    harness = await MemoraHarness.create();
  });

  // -------------------------------------------------------------------------
  // 1. Add images
  // -------------------------------------------------------------------------

  test(
    'files copied images as captured memories and skips a duplicate',
    () async {
      final report = await harness.importAll();

      expect(report.addedIds, hasLength(4));
      expect(report.duplicateCount, 1);
      expect(report.duplicatePaths, [augustBillCopy.imagePath]);

      // Nothing points at the skipped copy, so the ingestor removes it.
      expect(harness.images.deleteRequests, [augustBillCopy.imagePath]);
      expect(harness.images.exists(augustBillCopy.imagePath), isFalse);
      expect((await harness.db.memories.storageStats()).memoryCount, 4);

      final memories = await harness.db.memories.listMemories(
        const MemoryListQuery(),
      );
      expect(memories, hasLength(4));
      expect(
        memories.map((m) => m.status),
        everyElement(ProcessingStatus.captured),
      );
      expect(memories.map((m) => m.source), everyElement(MemorySource.gallery));
      expect(memories.map((m) => m.summary), everyElement(isNull));

      // A thumbnail was asked for every memory that was added, and only those.
      expect(harness.images.thumbnailRequests, [
        for (final fixture in imageFixtures) fixture.imagePath,
      ]);
      for (final memory in memories) {
        expect(memory.thumbnailPath, isNotNull, reason: memory.id);
        expect(harness.images.exists(memory.thumbnailPath!), isTrue);
      }

      final august = (await harness.db.memories.getMemory(harness.augustId))!;
      expect(august.imagePath, augustBill.imagePath);
      expect(august.sha256, augustBill.sha256);
      expect(august.mimeType, 'image/png');
      // Timestamp columns hold instants, and the database reads them back as
      // UTC whatever zone they went in as.
      expect(august.takenAt.isUtc, isTrue);
      expect(august.takenAt.toLocal(), augustBill.takenAt);
      expect(august.addedAt.toLocal(), harness.clock.current);

      final summary = await harness.db.memories.queueSummary();
      expect(summary.total, 4);
      expect(summary.waiting, 4);
      expect(summary.ready, 0);
      expect(await harness.db.queue.hasWork(harness.clock.now()), isTrue);
    },
  );

  // -------------------------------------------------------------------------
  // 2. Process the queue
  // -------------------------------------------------------------------------

  test('understands every queued memory and records what did it', () async {
    await harness.importAll();
    harness.clock.advance(const Duration(hours: 3));
    final report = await harness.processAll();

    expect(report.processed, 4);
    expect(report.remaining, isFalse);
    expect(report.block, isNull);
    expect(report.nextAttemptAt, isNull);

    final summary = await harness.db.memories.queueSummary();
    expect(summary.ready, 4);
    expect(summary.waiting, 0);
    expect(summary.processing, 0);
    expect(summary.failed, 0);

    // The queue hands out the oldest taken image first.
    expect(
      [
        for (final request in harness.vision.analyzeRequests)
          request.absoluteImagePath!.split('/').last,
      ],
      [
        augustBill.fileName,
        laptopComparison.fileName,
        flightBooking.fileName,
        septemberBill.fileName,
      ],
    );
    final firstRequest = harness.vision.analyzeRequests.first;
    expect(firstRequest.mimeType, 'image/png');
    expect(firstRequest.takenAt.toLocal(), augustBill.takenAt);
    expect(firstRequest.defaultCurrency, 'INR');
    expect(firstRequest.imageBytes, augustBill.bytes);

    final details = (await harness.db.memories.getDetails(harness.augustId))!;
    expect(details.memory.status, ProcessingStatus.ready);
    expect(details.memory.processedAt!.toLocal(), harness.clock.current);
    expect(details.memory.summary, 'Reliance electricity bill for August 2026');
    expect(details.memory.category, 'utility_bill');
    expect(details.memory.visualDescription, isNotEmpty);
    expect(details.memory.extractedText, contains('Amount due Rs 1,842'));
    expect(details.memory.failureReason, isNull);

    expect(details.entities, hasLength(1));
    expect(details.entities.single.type, 'company');
    expect(details.entities.single.value, 'Reliance Energy');
    expect(details.entities.single.normalizedValue, 'reliance energy');

    final amount = details.attributes.firstWhere((a) => a.type == 'amount');
    expect(amount.value, formatMoney(1842, 'INR'));
    expect(amount.valueNum, 1842.0);
    expect(amount.currency, 'INR');
    expect(amount.label, 'total');
    final due = details.attributes.firstWhere((a) => a.type == 'due_date');
    expect(due.valueDate, '2026-08-31');
    expect(due.value, '31 Aug 2026');
    final account = details.attributes.firstWhere(
      (a) => a.type == 'account_number',
    );
    expect(account.value, '.... 4471');
    expect(account.valueNum, isNull);
    expect(details.keywords, ['reliance', 'electricity', 'bill', 'august']);

    final visionRecord = details.processing.firstWhere(
      (record) => record.capability == Capability.vision,
    );
    expect(visionRecord.provider, MemoraHarness.providerId);
    expect(visionRecord.model, MemoraHarness.visionModel);
    expect(visionRecord.outcome, ProcessingOutcome.succeeded);
    expect(visionRecord.error, isNull);
    final embeddingRecord = details.processing.firstWhere(
      (record) => record.capability == Capability.embeddings,
    );
    expect(embeddingRecord.provider, MemoraHarness.providerId);
    expect(embeddingRecord.model, MemoraHarness.embeddingModel);
    expect(embeddingRecord.version, '1');
    expect(embeddingRecord.outcome, ProcessingOutcome.succeeded);

    // Every memory carries facts, an index row and a vector.
    for (final id in harness.importedIds) {
      final each = (await harness.db.memories.getDetails(id))!;
      expect(each.memory.status, ProcessingStatus.ready, reason: id);
      expect(each.entities, isNotEmpty, reason: id);
      expect(each.attributes, isNotEmpty, reason: id);
      expect(each.keywords, isNotEmpty, reason: id);
      expect(each.processing, hasLength(2), reason: id);
      expect(harness.hasFtsRow(harness.seqOf(id)), isTrue, reason: id);
      expect(harness.countFor('embeddings', id), 1, reason: id);
    }
    expect(await harness.db.vectors.countFor(harness.embeddings.model), 4);
    expect(
      await harness.db.vectors.missingFor(harness.embeddings.model),
      isEmpty,
    );

    // Vectors come from the understanding, not from raw text.
    expect(harness.embeddings.calls, hasLength(4));
    expect(
      harness.embeddings.purposes,
      everyElement(EmbeddingPurpose.document),
    );
    final embedded = harness.embeddings.calls.first.single;
    expect(
      embedded,
      startsWith(
        'Reliance electricity bill for August 2026\n'
        'Category: utility_bill\n',
      ),
    );
    expect(embedded, contains('Entities: Reliance Energy'));
    expect(embedded, contains('Keywords: reliance, electricity, bill, august'));
    expect(
      embedded,
      contains(
        'Facts: amount: ${formatMoney(1842, 'INR')}; '
        'due_date: 31 Aug 2026; account_number: .... 4471',
      ),
    );
  });

  // -------------------------------------------------------------------------
  // 3. Structured retrieval
  // -------------------------------------------------------------------------

  test(
    'structured filters keep the bill and leave the comparison out',
    () async {
      await harness.importAndProcess();

      final result = await harness.retrieval.search(
        RetrievalQuery(
          entities: const [EntityFilter(value: 'Reliance', type: 'company')],
          attributes: const [
            AttributeFilter(type: 'amount', min: 1800, currency: 'INR'),
          ],
          takenBetween: DateRange.month(2026, 8),
          strategies: const {RetrievalStrategy.structured},
        ),
      );

      expect(result.strategiesUsed, {RetrievalStrategy.structured});
      expect([for (final hit in result.hits) hit.card.id], [harness.augustId]);
      expect(
        result.hits.single.foundBy,
        contains(RetrievalStrategy.structured),
      );
      expect(result.hits.single.card.category, 'utility_bill');
      expect(result.hits.single.card.facts['amount'], formatMoney(1842, 'INR'));
      expect(result.hits.single.card.facts['due_date'], '31 Aug 2026');

      // A card carries the names on it, which is what a reranker matches a
      // question against.
      final card = (await harness.db.search.cards([harness.augustId])).single;
      expect(card.entities, ['Reliance Energy']);
      expect(
        DefaultRetrievalEngine.cardSearchText(card),
        contains('Reliance Energy'),
      );

      // The comparison was taken the same month and holds amounts far over the
      // floor, so only the entity filter keeps it out.
      final laptop = (await harness.db.memories.getDetails(harness.laptopId))!;
      expect(laptop.memory.takenAt.month, 8);
      expect(
        laptop.attributes.map((a) => a.valueNum),
        everyElement(isNot(lessThan(1800))),
      );

      // The September bill is over the floor but outside the month.
      final wholeQuarter = await harness.retrieval.search(
        RetrievalQuery(
          entities: const [EntityFilter(value: 'Reliance', type: 'company')],
          attributes: const [
            AttributeFilter(type: 'amount', min: 1800, currency: 'INR'),
          ],
          takenBetween: DateRange(
            start: DateTime(2026, 8),
            end: DateTime(2026, 10),
          ),
          strategies: const {RetrievalStrategy.structured},
        ),
      );
      expect(
        [for (final hit in wholeQuarter.hits) hit.card.id],
        [harness.septemberId, harness.augustId],
      );

      // And the amount floor really bites.
      final higherFloor = await harness.retrieval.search(
        RetrievalQuery(
          entities: const [EntityFilter(value: 'Reliance', type: 'company')],
          attributes: const [
            AttributeFilter(type: 'amount', min: 1900, currency: 'INR'),
          ],
          takenBetween: DateRange.month(2026, 8),
          strategies: const {RetrievalStrategy.structured},
        ),
      );
      expect(higherFloor.hits, isEmpty);
    },
  );

  // -------------------------------------------------------------------------
  // 4. Text and semantic retrieval
  // -------------------------------------------------------------------------

  test('a word that only appears in extracted text finds its memory', () async {
    await harness.importAndProcess();

    final september = (await harness.db.memories.getMemory(
      harness.septemberId,
    ))!;
    expect(september.extractedText, contains('Dahisar'));
    expect(september.summary, isNot(contains('Dahisar')));
    expect(
      (await harness.db.memories.getDetails(harness.septemberId))!.keywords,
      isNot(contains('dahisar')),
    );

    final result = await harness.retrieval.search(
      const RetrievalQuery(
        text: 'Dahisar',
        strategies: {RetrievalStrategy.text},
      ),
    );
    expect(result.strategiesUsed, {RetrievalStrategy.text});
    expect(result.textMatched, isTrue);
    expect([for (final hit in result.hits) hit.card.id], [harness.septemberId]);
    expect(result.hits.single.foundBy, contains(RetrievalStrategy.text));
  });

  test(
    'a semantic query finds a memory that shares none of its words',
    () async {
      await harness.importAndProcess();
      const asked = 'getting to the airport';

      final byWords = await harness.retrieval.search(
        const RetrievalQuery(text: asked, strategies: {RetrievalStrategy.text}),
      );
      expect(
        byWords.hits,
        isEmpty,
        reason: 'no memory uses the words of "$asked"',
      );

      // The vectors, which this test writes, say the booking and nothing else.
      final vectors = await harness.db.vectors.search(
        harness.embeddings.vectorFor(asked),
        harness.embeddings.model,
      );
      expect(vectors.first.id, harness.flightId);
      expect(vectors.first.score, closeTo(1, 1e-6));
      expect([
        for (final scored in vectors.skip(1)) scored.score,
      ], everyElement(closeTo(0, 1e-6)));

      final byMeaning = await harness.retrieval.search(
        const RetrievalQuery(
          text: asked,
          strategies: {RetrievalStrategy.semantic},
        ),
      );
      expect(byMeaning.strategiesUsed, {RetrievalStrategy.semantic});
      expect(byMeaning.hits.first.card.id, harness.flightId);
      expect(
        byMeaning.hits.first.foundBy,
        contains(RetrievalStrategy.semantic),
      );
      expect(byMeaning.hits.first.card.facts['pnr'], 'K7X9QW');
      expect(harness.embeddings.calls.last.single, asked);
      expect(harness.embeddings.purposes.last, EmbeddingPurpose.query);

      // And it leads although three memories were taken after it, so the
      // similarity decided the order rather than the recency tie-break.
      final newest = await harness.db.memories.listMemories(
        const MemoryListQuery(limit: 1),
      );
      expect(newest.single.id, harness.septemberId);
      expect(
        byMeaning.hits
            .map((hit) => hit.card.id)
            .toList()
            .indexOf(harness.septemberId),
        greaterThan(0),
      );
    },
  );

  // -------------------------------------------------------------------------
  // 5. Ask with a chat model
  // -------------------------------------------------------------------------

  test(
    'the agent answers through real tools and cites real memories',
    () async {
      await harness.importAndProcess();
      final (conversation, answer) = await askWithModel(harness);

      expect((await harness.chatEngine.availability()).searchOnly, isFalse);
      expect(harness.chat.requests, hasLength(3));
      expect([
        for (final tool in harness.chat.requests.first.tools) tool.name,
      ], containsAll(['search_by_entity', 'aggregate_results', 'get_memory']));

      // Read the answer back out of the database, not off the stream.
      final saved = await harness.db.conversations.messages(conversation.id);
      expect(saved.map((m) => m.role), [
        MessageRole.user,
        MessageRole.assistant,
      ]);
      expect(saved.first.content, question);
      final assistant = saved.last;
      expect(assistant.id, answer.id);
      expect(assistant.provider, MemoraHarness.providerId);
      expect(assistant.model, MemoraHarness.chatModel);
      expect(assistant.content, contains(formatMoney(2103, 'INR')));
      expect(assistant.content, isNot(contains('[[m:')));

      // Every reference names a memory that is really there.
      expect(
        [for (final r in assistant.references) r.memoryId],
        [harness.septemberId, harness.augustId],
      );
      expect([for (final r in assistant.references) r.position], [0, 1]);
      for (final reference in assistant.references) {
        expect(
          await harness.db.memories.getMemory(reference.memoryId),
          isNotNull,
        );
        expect(reference.relevance, isNotNull);
      }

      expect(
        [for (final entry in assistant.toolTrace) entry.tool],
        ['search_by_entity', 'aggregate_results'],
      );
      expect(assistant.toolTrace.first.arguments, {
        'value': 'Reliance',
        'type': 'company',
      });
      expect(assistant.toolTrace.first.summary, '2 candidates');
      expect(assistant.toolTrace.last.arguments, {
        'op': 'max',
        'attribute': 'amount',
      });
      expect(assistant.toolTrace.last.summary, formatMoney(2103, 'INR'));

      final presentation = assistant.presentation!;
      expect(presentation.layout, SourceLayout.table);
      expect(presentation.tableAttribute, 'amount');
      expect(presentation.headline, formatMoney(2103, 'INR'));
      expect(presentation.highlightMemoryId, harness.septemberId);
      expect(presentation.sourceLabel, '2 memories · entity');
      expect(presentation.searchOnly, isFalse);

      // The headline came from one memory's attribute, so it was checked
      // against that image.
      expect(presentation.verification, VerificationState.verified);
      expect(presentation.headlineNote, AnswerVerifier.verifiedNote);
      expect(harness.vision.verifyRequests, hasLength(1));
      expect(harness.vision.verifyRequests.single.attributeType, 'amount');
      expect(
        harness.vision.verifyRequests.single.expectedValue,
        formatMoney(2103, 'INR'),
      );
      expect(
        harness.vision.verifyRequests.single.absoluteImagePath,
        harness.images.absolutePath(septemberBill.imagePath),
      );

      // The search the agent ran is the conversation's active result set.
      final active = (await harness.db.conversations.latestResultSet(
        conversation.id,
      ))!;
      expect(active.memoryIds, [harness.septemberId, harness.augustId]);
      expect(active.messageId, assistant.id);
    },
  );

  // -------------------------------------------------------------------------
  // 6. Ask without a chat model
  // -------------------------------------------------------------------------

  test(
    'search alone answers which was highest and says it was search only',
    () async {
      await harness.importAndProcess();
      await harness.removeChatModel();

      expect((await harness.chatEngine.availability()).searchOnly, isTrue);

      final (conversation, answer) = await askWithoutModel(harness);
      expect(harness.chat.requests, isEmpty);

      expect(answer.provider, isNull);
      expect(answer.model, isNull);
      expect(answer.content, startsWith('Found 2 memories matching reliance'));
      expect(
        answer.content,
        contains('The highest amount is ${formatMoney(2103, 'INR')}'),
      );
      expect(answer.content, contains('Sep 2026'));

      final presentation = answer.presentation!;
      expect(presentation.searchOnly, isTrue);
      expect(presentation.layout, SourceLayout.table);
      expect(presentation.tableAttribute, 'amount');
      expect(presentation.headline, formatMoney(2103, 'INR'));
      expect(presentation.highlightMemoryId, harness.septemberId);
      expect(presentation.verification, VerificationState.none);

      // Both bills are cited. Which one reads first is the search ranking, and
      // the answer names the highest from the stored amounts either way.
      expect([
        for (final r in answer.references) r.memoryId,
      ], unorderedEquals([harness.septemberId, harness.augustId]));
      expect(
        [for (final entry in answer.toolTrace) entry.tool],
        ['search_memories', 'aggregate_results'],
      );
      expect(answer.toolTrace.first.arguments['text'], 'reliance');
      expect(answer.toolTrace.last.summary, formatMoney(2103, 'INR'));

      // It is saved the same way a model answer is.
      final saved = await harness.db.conversations.messages(conversation.id);
      expect(saved.last.id, answer.id);
      expect(saved.last.presentation!.searchOnly, isTrue);
    },
  );

  // -------------------------------------------------------------------------
  // 7. Delete and export
  // -------------------------------------------------------------------------

  test(
    'deleting a memory takes its facts with it and export describes the rest',
    () async {
      await harness.importAndProcess();
      final (modelConversation, _) = await askWithModel(harness);
      harness.clock.advance(const Duration(minutes: 5));
      await harness.removeChatModel();
      final (searchConversation, _) = await askWithoutModel(harness);

      final seq = harness.seqOf(harness.laptopId);
      final files = await harness.db.memories.deleteMemory(harness.laptopId);

      expect(files, isNotNull);
      expect(files!.imagePath, laptopComparison.imagePath);
      expect(files.thumbnailPath, isNotNull);
      expect(files.all, hasLength(2));

      expect(await harness.db.memories.getMemory(harness.laptopId), isNull);
      expect(await harness.db.memories.getDetails(harness.laptopId), isNull);
      for (final table in const [
        'entities',
        'attributes',
        'keywords',
        'embeddings',
        'processing_metadata',
      ]) {
        expect(harness.countFor(table, harness.laptopId), 0, reason: table);
      }
      expect(harness.hasFtsRow(seq), isFalse);
      expect(await harness.db.vectors.countFor(harness.embeddings.model), 3);

      final gone = await harness.retrieval.search(
        const RetrievalQuery(
          text: 'ThinkPad',
          strategies: {RetrievalStrategy.text},
        ),
      );
      expect(gone.hits, isEmpty);

      // The store reports the files; removing them is the caller's job.
      expect(harness.images.exists(files.imagePath), isTrue);
      await harness.images.delete(files.all);
      expect(harness.images.exists(files.imagePath), isFalse);
      expect(harness.images.exists(files.thumbnailPath!), isFalse);

      // ---- export -----------------------------------------------------------

      final manifest = await harness.export.manifest();
      expect(manifest.memoryCount, 3);
      expect(manifest.conversationCount, 2);
      expect(manifest.toJson(), {
        'format': ExportManifest.formatName,
        'format_version': ExportManifest.formatVersion,
        'exported_at': harness.clock.current.toUtc().toIso8601String(),
        'app_version': '0.1.0',
        'counts': {'memories': 3, 'conversations': 2, 'images': 3},
      });

      final records = await harness.export.memories().toList();
      expect(
        [for (final record in records) record.memory.id],
        [harness.augustId, harness.flightId, harness.septemberId],
      );

      final august = records.first.toJson();
      expect(august['id'], harness.augustId);
      expect(august['image_file'], 'images/${harness.augustId}.png');
      expect(august['source_path'], augustBill.imagePath);
      expect(august['sha256'], augustBill.sha256);
      expect(august['status'], 'ready');
      expect(august['source'], 'gallery');
      expect(august['category'], 'utility_bill');
      expect(august['summary'], 'Reliance electricity bill for August 2026');
      expect(august['extracted_text'], contains('Amount due Rs 1,842'));
      expect(august['entities'], [
        {
          'type': 'company',
          'value': 'Reliance Energy',
          'normalized_value': 'reliance energy',
        },
      ]);
      expect(august['keywords'], ['reliance', 'electricity', 'bill', 'august']);

      final attributes = jsonRows(august['attributes']);
      expect(attributes.firstWhere((a) => a['type'] == 'amount'), {
        'type': 'amount',
        'value': formatMoney(1842, 'INR'),
        'value_num': 1842.0,
        'currency': 'INR',
        'label': 'total',
      });
      expect(attributes.firstWhere((a) => a['type'] == 'due_date'), {
        'type': 'due_date',
        'value': '31 Aug 2026',
        'value_date': '2026-08-31',
      });

      expect([
        for (final row in jsonRows(august['processing'])) row['capability'],
      ], containsAll(['vision', 'embeddings']));
      expect(august['embeddings'], [
        {
          'model_id': 'scripted/${MemoraHarness.embeddingModel}',
          'version': '1',
          'dimensions': AxisEmbeddingService.dimensions,
        },
      ]);

      final conversations = await harness.export.conversations().toList();
      expect(conversations, hasLength(2));

      final withModel = conversations.firstWhere(
        (c) => c['id'] == modelConversation.id,
      );
      expect(withModel['title'], question);
      final modelMessages = jsonRows(withModel['messages']);
      expect(modelMessages, hasLength(2));
      expect(modelMessages.first['role'], 'user');
      expect(modelMessages.first['content'], question);
      final assistant = modelMessages.last;
      expect(assistant['role'], 'assistant');
      expect(assistant['provider'], MemoraHarness.providerId);
      expect(assistant['model'], MemoraHarness.chatModel);
      expect(
        [for (final row in jsonRows(assistant['references'])) row['memory_id']],
        [harness.septemberId, harness.augustId],
      );
      expect(
        [for (final row in jsonRows(assistant['tool_trace'])) row['tool']],
        ['search_by_entity', 'aggregate_results'],
      );
      final exportedPresentation = assistant['presentation']! as Map;
      expect(exportedPresentation['layout'], 'table');
      expect(exportedPresentation['headline'], formatMoney(2103, 'INR'));
      expect(exportedPresentation['verification'], 'verified');
      final activeSet = withModel['active_result_set']! as Map;
      expect(activeSet['memory_ids'], [harness.septemberId, harness.augustId]);

      final searchOnly = conversations.firstWhere(
        (c) => c['id'] == searchConversation.id,
      );
      final searchMessages = jsonRows(searchOnly['messages']);
      expect(searchMessages, hasLength(2));
      expect(searchMessages.last['provider'], isNull);
      expect(
        (searchMessages.last['presentation']! as Map)['search_only'],
        isTrue,
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Steps reused by more than one test
// ---------------------------------------------------------------------------

/// Drives one turn with a chat model: a search, then an aggregate, then an
/// answer that cites the memories it used.
Future<(Conversation, ChatMessage)> askWithModel(MemoraHarness harness) async {
  harness.chat.script.addAll([
    toolTurn([
      ToolCall(
        id: 'call-1',
        name: 'search_by_entity',
        arguments: const {'value': 'Reliance', 'type': 'company'},
      ),
    ]),
    toolTurn([
      ToolCall(
        id: 'call-2',
        name: 'aggregate_results',
        arguments: const {'op': 'max', 'attribute': 'amount'},
      ),
    ]),
    answerTurn(
      'Your September bill was the highest at ${formatMoney(2103, 'INR')} '
      '[[m:${harness.septemberId}]], up from ${formatMoney(1842, 'INR')} in '
      'August [[m:${harness.augustId}]].',
    ),
  ]);
  return _askOnce(harness);
}

Future<(Conversation, ChatMessage)> askWithoutModel(MemoraHarness harness) =>
    _askOnce(harness);

Future<(Conversation, ChatMessage)> _askOnce(MemoraHarness harness) async {
  final conversation = await harness.chatEngine.startConversation(
    title: question,
  );
  final events = await ask(harness.chatEngine, conversation.id, question);
  return (conversation, answerFrom(events));
}

/// Reads a list of JSON objects out of an exported record.
List<Map<String, Object?>> jsonRows(Object? value) => [
  for (final row in value! as List) row as Map<String, Object?>,
];
