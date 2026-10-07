import 'dart:convert';
import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';
import 'package:memora_providers/memora_providers.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';

const _searchTool = ToolDefinition(
  name: 'search_memories',
  description:
      'Hybrid search with optional text, category and entity.\nThe '
      'workhorse.',
  parameters: {
    'type': 'object',
    'properties': {
      'text': {'type': 'string'},
      'limit': {'type': 'integer'},
    },
    'required': ['text'],
  },
);

const _getTool = ToolDefinition(
  name: 'get_memory',
  description: 'Full details for one memory.',
  parameters: {
    'type': 'object',
    'properties': {
      'id': {'type': 'string'},
    },
    'required': ['id'],
  },
);

ChatRequest _ask(
  String question, {
  List<ToolDefinition> tools = const [_searchTool, _getTool],
  List<ChatEntry> entries = const [],
  String system = 'You answer questions about saved images.',
}) => ChatRequest(
  system: system,
  entries: entries.isEmpty ? [UserEntry(question)] : entries,
  tools: tools,
);

VisionRequest _vision({Uint8List? bytes}) => VisionRequest(
  imageBytes: bytes ?? Uint8List.fromList([1, 2, 3]),
  mimeType: 'image/png',
  takenAt: DateTime(2026, 9, 1),
  absoluteImagePath: '/data/files/originals/a.png',
);

const _understanding = {
  'summary': 'Reliance electricity bill for August 2026',
  'category': 'utility_bill',
  'visual_description': 'A utility bill in a mobile app.',
  'extracted_text': 'Amount due 1842',
  'keywords': ['reliance', 'bill'],
  'entities': [
    {'type': 'company', 'value': 'Reliance'},
  ],
  'dates': [
    {'type': 'due_date', 'value': '2026-08-31'},
  ],
  'amounts': [
    {'type': 'total', 'value': 1842, 'currency': 'INR'},
  ],
  'attributes': <Map<String, Object?>>[],
  'confidence': 0.86,
};

void main() {
  late ScriptedLlmRuntime llm;
  late FakeLocalLlmFiles llmFiles;
  late FakeOcrEngine ocr;

  setUp(() {
    llm = ScriptedLlmRuntime();
    llmFiles = FakeLocalLlmFiles();
    ocr = FakeOcrEngine();
  });

  LocalRuntime local({bool withLlm = true}) => LocalRuntime(
    ocr: ocr,
    embeddingRuntime: FakeEmbeddingRuntime(),
    modelFiles: FakeLocalModelFiles(),
    llm: withLlm ? llm : null,
    llmFiles: withLlm ? llmFiles : null,
  );

  LocalProviderClient client({bool withLlm = true}) =>
      LocalProviderClient(local(withLlm: withLlm));

  group('catalog', () {
    test('describes the models a user can bring', () {
      expect(localLlmCatalog, [gemma3_1b, gemma3nE2b]);
      expect(localLlmSpec('gemma-3-1b-it-int4'), same(gemma3_1b));
      expect(localLlmSpec('bge-small-en-v1.5'), isNull);

      expect(gemma3_1b.displayName, 'Gemma 3 1B');
      expect(gemma3_1b.vision, isFalse);
      expect(gemma3_1b.approximateBytes, 550 * 1024 * 1024);
      expect(gemma3_1b.requiredMemoryBytes, 2 * 1024 * 1024 * 1024);

      expect(gemma3nE2b.displayName, 'Gemma 3n E2B');
      expect(gemma3nE2b.vision, isTrue);
      expect(gemma3nE2b.approximateBytes, 3 * 1024 * 1024 * 1024);
      expect(gemma3nE2b.requiredMemoryBytes, 4 * 1024 * 1024 * 1024);
    });

    test('every entry names its licence and where the file comes from', () {
      for (final spec in localLlmCatalog) {
        expect(spec.licence, 'Gemma Terms of Use', reason: spec.id);
        expect(spec.sourceName, isNotEmpty, reason: spec.id);
        expect(spec.sourceUrl, startsWith('https://'), reason: spec.id);
        expect(spec.fileExtensions, ['.task', '.litertlm'], reason: spec.id);
      }
    });

    test('the provider offers chat and the generative vision model', () {
      expect(localDescriptor.capabilities, contains(Capability.chat));
      expect(localDescriptor.defaultModel(Capability.chat), gemma3_1b.id);
      expect(localDescriptor.suggestedModels[Capability.vision], [
        'ocr-rules',
        gemma3nE2b.id,
      ]);
    });
  });

  group('prompt', () {
    test('puts the system text and tools in the first user turn', () {
      final prompt = LocalLlmPrompt.chat(_ask('how much was my bill?'));

      expect(prompt, startsWith('<start_of_turn>user\n'));
      expect(prompt, endsWith('<start_of_turn>model\n'));
      expect(prompt, contains('You answer questions about saved images.'));
      expect(
        prompt,
        contains(
          '- search_memories(text: string, limit?: integer): '
          'Hybrid search with optional text, category and entity. The '
          'workhorse.',
        ),
      );
      expect(prompt, contains('- get_memory(id: string): Full details'));
      expect(prompt, contains('{"tool": "<name>", "arguments": {}}'));
      expect(prompt, contains('how much was my bill?<end_of_turn>'));
    });

    test('writes earlier turns, calls and results in order', () {
      final prompt = LocalLlmPrompt.chat(
        _ask(
          'and september?',
          entries: const [
            UserEntry('august bill?'),
            AssistantEntry(
              toolCalls: [
                ToolCall(
                  id: 'c1',
                  name: 'search_memories',
                  arguments: {'text': 'august bill'},
                ),
              ],
            ),
            ToolResultEntry(
              callId: 'c1',
              toolName: 'search_memories',
              content: '{"count":3}',
            ),
            AssistantEntry(text: 'It was 2,103 rupees.'),
            UserEntry('and september?'),
          ],
        ),
      );

      expect(prompt.split('<start_of_turn>').map((t) => t.split('\n').first), [
        '',
        'user',
        'model',
        'user',
        'model',
        'user',
        'model',
      ]);
      expect(
        prompt,
        contains(
          '{"tool":"search_memories","arguments":{"text":"august '
          'bill"}}',
        ),
      );
      expect(prompt, contains('Result from search_memories:\n{"count":3}'));
      expect(prompt, contains('It was 2,103 rupees.'));
    });

    test('clips a long tool result', () {
      final prompt = LocalLlmPrompt.chat(
        _ask(
          'x',
          entries: [
            const UserEntry('x'),
            const AssistantEntry(
              toolCalls: [
                ToolCall(id: 'c1', name: 'search_memories', arguments: {}),
              ],
            ),
            ToolResultEntry(
              callId: 'c1',
              toolName: 'search_memories',
              content: 'y' * 4000,
            ),
          ],
        ),
      );

      expect(prompt, contains('…'));
      expect(prompt.length, lessThan(3000));
    });

    test('reads a tool call out of whatever the model wrote', () {
      const allowed = {'search_memories'};
      ToolCall? parse(String text) =>
          parseLocalToolCall(text, allowed, id: 'c1');

      expect(
        parse('{"tool": "search_memories", "arguments": {"text": "bill"}}')
            ?.arguments,
        {'text': 'bill'},
      );
      expect(
        parse(
          'Sure, I will look.\n```json\n{"name":"search_memories",'
          '"args":{"text":"bill"}}\n```',
        )?.name,
        'search_memories',
      );
      expect(
        parse('{"tool":"search_memories","parameters":"{\\"text\\":\\"a\\"}"}')
            ?.arguments,
        {'text': 'a'},
      );
      expect(parse('{"tool":"search_memories"}')?.arguments, isEmpty);
      expect(parse('I think it was about 2,000 rupees.'), isNull);
      expect(parse('{"tool":"look_it_up","arguments":{}}'), isNull);
      expect(parse('{"text":"bill"}'), isNull);
    });
  });

  group('chat', () {
    ChatService chatService({String modelId = 'gemma-3-1b-it-int4'}) =>
        client().chat(modelId)!;

    test('loads the imported file once and streams the reply', () async {
      llmFiles.install('gemma-3-1b-it-int4', path: 'models/gemma.task');
      llm.script
        ..add(['{"tool": "search_', 'memories", "arguments": ', '{}}'])
        ..add(['Your August bill was ', '2,103 rupees.', '<end_of_turn>']);
      final service = chatService();

      final first = await service.complete(_ask('august bill?'));
      final second = await service.complete(
        _ask(
          'august bill?',
          entries: const [
            UserEntry('august bill?'),
            AssistantEntry(
              toolCalls: [
                ToolCall(id: 'c1', name: 'search_memories', arguments: {}),
              ],
            ),
            ToolResultEntry(
              callId: 'c1',
              toolName: 'search_memories',
              content: '{"count":1}',
            ),
          ],
        ),
      );

      expect(first.stopReason, ChatStopReason.toolUse);
      expect(first.toolCalls.single.name, 'search_memories');
      expect(second.stopReason, ChatStopReason.endTurn);
      expect(second.text, 'Your August bill was 2,103 rupees.');
      expect(llm.loads, [
        (path: 'models/gemma.task', vision: false, maxTokens: 4096),
      ]);
      expect(llm.prompts.first.images, isEmpty);
    });

    test('stops reading at the end of the turn', () async {
      llmFiles.install('gemma-3-1b-it-int4');
      llm.script.add([
        'Found it.',
        '<end_of_turn>',
        '<start_of_turn>user\nwhat else?',
        'and more invented turns',
      ]);

      final turn = await chatService().complete(_ask('x', tools: const []));

      expect(turn.text, 'Found it.');
      expect(llm.cancelled, isTrue);
      expect(llm.delivered.single, hasLength(2));
    });

    test('stops reading when the model runs away', () async {
      llmFiles.install('gemma-3-1b-it-int4');
      llm.script.add([for (var i = 0; i < 40; i++) 'x' * 100]);

      final turn = await chatService().complete(
        const ChatRequest(
          system: '',
          entries: [UserEntry('x')],
          maxOutputTokens: 100,
        ),
      );

      expect(turn.text.length, lessThanOrEqualTo(700));
      expect(llm.cancelled, isTrue);
    });

    test('hands the turn back to search when no call comes out', () async {
      llmFiles.install('gemma-3-1b-it-int4');
      llm.script.add(['I think your bill was about 2,000 rupees.']);

      await expectLater(
        chatService().complete(_ask('august bill?')),
        throwsA(
          isA<ToolCallingUnavailableException>()
              .having((e) => e.providerId, 'providerId', 'local')
              .having((e) => e.modelId, 'modelId', 'gemma-3-1b-it-int4'),
        ),
      );
    });

    test('a context size the file cannot hold is tried smaller', () async {
      llmFiles.install('gemma-3-1b-it-int4');
      // The .task bundle was built for less than the catalog asks for.
      llm.refuseTokens.addAll({4096, 2048});
      llm.script.add(['Hello.']);

      final turn = await chatService().complete(_ask('hi', tools: const []));

      expect(turn.text, 'Hello.');
      expect(llm.loads.map((l) => l.maxTokens), [
        4096,
        2048,
        1280,
      ], reason: 'largest first, until one loads');
    });

    test('a model nothing can load gives up and says why', () async {
      llmFiles.install('gemma-3-1b-it-int4');
      llm.refuseTokens.addAll({4096, 2048, 1280, 512});

      await expectLater(
        chatService().complete(_ask('hi', tools: const [])),
        throwsA(isA<AiConfigurationException>()),
      );
      expect(llm.loads.map((l) => l.maxTokens), [
        4096,
        2048,
        1280,
        512,
      ], reason: 'every size tried before giving up');
    });

    test('running out of memory is not retried at a smaller size', () async {
      llmFiles.install('gemma-3-1b-it-int4');
      llm.loadError = AiConfigurationException(
        'The device ran out of memory while loading the model.',
        providerId: 'local',
      );

      await expectLater(
        chatService().complete(_ask('hi', tools: const [])),
        throwsA(isA<AiConfigurationException>()),
      );
      expect(
        llm.loads,
        hasLength(1),
        reason: 'a smaller context does not conjure up memory',
      );
    });

    test('a general question gets its plain answer, not a search', () async {
      llmFiles.install('gemma-3-1b-it-int4');
      llm.script.add(['A kilowatt hour is a unit of energy.']);

      final turn = await chatService().complete(_ask('what does kWh mean?'));

      expect(turn.text, 'A kilowatt hour is a unit of energy.');
      expect(turn.toolCalls, isEmpty);
      expect(turn.stopReason, ChatStopReason.endTurn);
    });

    test('an invented tool name is not a call', () async {
      llmFiles.install('gemma-3-1b-it-int4');
      llm.script.add(['{"tool": "ask_the_user", "arguments": {}}']);

      await expectLater(
        chatService().complete(_ask('august bill?')),
        throwsA(isA<ToolCallingUnavailableException>()),
      );
    });

    test('plain text is an answer once a tool has run', () async {
      llmFiles.install('gemma-3-1b-it-int4');
      llm.script.add(['It was 2,103 rupees.']);

      final turn = await chatService().complete(
        _ask(
          'august bill?',
          entries: const [
            UserEntry('august bill?'),
            AssistantEntry(
              toolCalls: [
                ToolCall(id: 'c1', name: 'search_memories', arguments: {}),
              ],
            ),
            ToolResultEntry(
              callId: 'c1',
              toolName: 'search_memories',
              content: '{"count":1}',
            ),
          ],
        ),
      );

      expect(turn.text, 'It was 2,103 rupees.');
      expect(turn.stopReason, ChatStopReason.endTurn);
    });

    test('plain text is an answer when no tools were offered', () async {
      llmFiles.install('gemma-3-1b-it-int4');
      llm.script.add(['Hello.']);

      final turn = await chatService().complete(_ask('hi', tools: const []));

      expect(turn.text, 'Hello.');
    });

    test('refuses before the file is imported', () async {
      await expectLater(
        chatService().complete(_ask('august bill?')),
        throwsA(
          isA<CapabilityUnavailableException>()
              .having((e) => e.capability, 'capability', Capability.chat)
              .having(
                (e) => e.reason,
                'reason',
                UnavailableReason.modelNotDownloaded,
              ),
        ),
      );
      expect(llm.loads, isEmpty);
    });

    test('a runtime that dies is worth retrying', () async {
      llmFiles.install('gemma-3-1b-it-int4');
      llm
        ..script.add(['Fou'])
        ..failWith = StateError('the engine was killed');

      await expectLater(
        chatService().complete(_ask('x', tools: const [])),
        throwsA(
          isA<AiTransientException>().having(
            (e) => e.providerId,
            'providerId',
            'local',
          ),
        ),
      );
    });

    test('reloads when the runtime lost the model', () async {
      llmFiles.install('gemma-3-1b-it-int4');
      llm.script
        ..add(['a'])
        ..add(['b']);
      final service = chatService();

      await service.complete(_ask('x', tools: const []));
      await llm.unload();
      await service.complete(_ask('x', tools: const []));

      expect(llm.loads, hasLength(2));
    });
  });

  group('vision', () {
    test('builds an understanding from the model JSON', () async {
      llmFiles.install(gemma3nE2b.id);
      llm.script.add([
        'Here it is:\n```json\n',
        jsonEncode(_understanding),
        '\n```<end_of_turn>',
      ]);
      final service = client().vision(gemma3nE2b.id)!;

      final understanding = await service.analyze(_vision());

      expect(
        understanding.summary,
        'Reliance electricity bill for August '
        '2026',
      );
      expect(understanding.category, 'utility_bill');
      expect(understanding.amounts.single.value, 1842);
      expect(llm.loads.single.vision, isTrue);
      expect(llm.prompts.single.images.single, [1, 2, 3]);
      expect(llm.prompts.single.prompt, contains('Return only JSON'));
      expect(
        llm.prompts.single.prompt,
        contains('Extract the memory data for this image.'),
      );
      expect(ocr.paths, isEmpty);
    });

    test('verify reads the value the model saw', () async {
      llmFiles.install(gemma3nE2b.id);
      llm.script.add([
        '{"confirmed": false, "observed_value": "2,130"}<end_of_turn>',
      ]);
      final service = client().vision(gemma3nE2b.id)!;

      final result = await service.verify(
        VerificationRequest(
          imageBytes: Uint8List.fromList([9]),
          mimeType: 'image/png',
          attributeType: 'amount',
          expectedValue: '2,103',
        ),
      );

      expect(result.confirmed, isFalse);
      expect(result.observedValue, '2,130');
    });

    test('prose instead of JSON fails that image', () async {
      llmFiles.install(gemma3nE2b.id);
      llm.script.add(['It looks like a bill of some kind.']);

      await expectLater(
        client().vision(gemma3nE2b.id)!.analyze(_vision()),
        throwsA(
          isA<AiContentException>().having(
            (e) => e.providerId,
            'providerId',
            'local',
          ),
        ),
      );
    });

    test('a text-only model keeps the OCR path', () async {
      llmFiles.install(gemma3_1b.id);
      ocr.result = ocrOf(['Reliance Energy', 'Amount due ₹1,842']);
      final service = client().vision(gemma3_1b.id)!;

      final understanding = await service.analyze(_vision());

      expect(understanding.extractedText, contains('Amount due'));
      expect(ocr.paths, ['/data/files/originals/a.png']);
      expect(llm.prompts, isEmpty);
      expect(llm.loads, isEmpty);

      final verified = await service.verify(
        VerificationRequest(
          imageBytes: Uint8List(0),
          mimeType: 'image/png',
          attributeType: 'amount',
          expectedValue: '₹1,842',
          absoluteImagePath: '/data/files/originals/a.png',
        ),
      );
      expect(verified.confirmed, isTrue);
      expect(llm.prompts, isEmpty);
    });

    test('ocr-rules is still the OCR service', () {
      expect(client().vision('ocr-rules'), isA<OcrVisionService>());
      expect(client().vision(gemma3nE2b.id), isA<LocalLlmVisionService>());
    });
  });

  group('the model list settings shows', () {
    LocalLlmModels models({
      int total = 8,
      int available = 5,
      bool lowRam = false,
    }) {
      llm.memoryState = DeviceMemory(
        totalBytes: total * 1024 * 1024 * 1024,
        availableBytes: available * 1024 * 1024 * 1024,
        lowRamDevice: lowRam,
      );
      return LocalLlmModels(runtime: llm, files: llmFiles);
    }

    test('says a big model does not fit a small phone', () async {
      final list = await models(total: 3, available: 2).list();

      expect(list.map((m) => m.spec.id), [gemma3_1b.id, gemma3nE2b.id]);
      expect(list.first.fit, LocalLlmFit.fits);
      expect(list.first.canImport, isTrue);
      expect(list.last.fit, LocalLlmFit.tooSmall);
      expect(
        list.last.canImport,
        isFalse,
        reason:
            'three gigabytes should not be offered to a phone that '
            'cannot hold the model',
      );
      expect(list.last.device!.totalBytes, 3 * 1024 * 1024 * 1024);
    });

    test('calls a phone with the RAM but none free tight', () async {
      final list = await models(total: 8, available: 1).list();

      expect(list.first.fit, LocalLlmFit.tight);
      expect(list.first.canImport, isTrue);
    });

    test('a low-RAM phone runs nothing', () async {
      final list = await models(lowRam: true).list();

      expect(list.map((m) => m.fit), everyElement(LocalLlmFit.tooSmall));
    });

    test('shows which file is installed', () async {
      llmFiles.install(gemma3_1b.id, sizeBytes: 1234);

      final list = await models().list();

      expect(list.first.isInstalled, isTrue);
      expect(list.first.installed!.sizeBytes, 1234);
      expect(list.first.canImport, isFalse);
      expect(list.last.isInstalled, isFalse);
    });

    test('imports a file and reports progress', () async {
      final events = await models().import(gemma3_1b.id).toList();

      expect(events.whereType<ModelImportCopying>().last.fraction, 0.5);
      expect(
        (events.last as ModelImportDone).model.relativePath,
        'models/gemma-3-1b-it-int4.task',
      );
      expect(llmFiles.imports.single.extensions, ['.task', '.litertlm']);
    });

    test('says plainly when the file is the wrong kind', () async {
      llmFiles.importScript = [
        const ModelImportRefused(
          ModelImportRefusal.wrongFileType,
          fileName: 'gemma-3-1b-it.gguf',
        ),
      ];

      final events = await models().import(gemma3_1b.id).toList();

      final refused = events.single as ModelImportRefused;
      expect(refused.reason, ModelImportRefusal.wrongFileType);
      expect(refused.fileName, 'gemma-3-1b-it.gguf');
      expect(llmFiles.models, isEmpty);
    });

    test('deleting the file unloads the model', () async {
      llmFiles.install(gemma3_1b.id);
      await llm.load('models/gemma.task', vision: false);

      await models().remove(gemma3_1b.id);

      expect(llmFiles.removals, [gemma3_1b.id]);
      expect(await llm.isLoaded(), isFalse);
      expect(llm.unloads, 1);
    });

    test('reports nothing to run on a build with no runtime', () async {
      const empty = LocalLlmModels();

      expect(empty.supported, isFalse);
      final list = await empty.list();
      expect(list.map((m) => m.fit), everyElement(LocalLlmFit.unknown));
      expect(list.first.device, isNull);
    });
  });

  group('client', () {
    test('offers chat and generative vision only with a runtime', () {
      expect(client().chat(gemma3_1b.id), isA<LocalLlmChatService>());
      expect(client().chat('gpt-6-sol'), isNull);
      expect(client(withLlm: false).chat(gemma3_1b.id), isNull);
      expect(client(withLlm: false).vision(gemma3nE2b.id), isNull);
      expect(
        client(withLlm: false).vision('ocr-rules'),
        isA<OcrVisionService>(),
      );
    });

    test('a model is only ready once its file is here', () async {
      final ready = client();

      expect(await ready.isModelReady(Capability.chat, gemma3_1b.id), isFalse);
      expect(await ready.isModelReady(Capability.vision, 'ocr-rules'), isTrue);
      expect(
        await ready.isModelReady(Capability.embeddings, 'bge-small-en-v1.5'),
        isTrue,
      );

      llmFiles.install(gemma3_1b.id);
      expect(await ready.isModelReady(Capability.chat, gemma3_1b.id), isTrue);
      expect(
        await client(withLlm: false)
            .isModelReady(Capability.chat, gemma3_1b.id),
        isFalse,
      );
    });

    test('lists the generative models only when one can run', () async {
      expect(await client().listModels(Capability.chat), [
        gemma3_1b.id,
        gemma3nE2b.id,
      ]);
      expect(await client(withLlm: false).listModels(Capability.chat), isEmpty);
      expect(await client(withLlm: false).listModels(Capability.vision), [
        'ocr-rules',
      ]);
    });

    test('testConnection mentions the imported model', () async {
      expect(
        (await client().testConnection()).detail,
        contains('A model you import'),
      );
      expect(
        (await client(withLlm: false).testConnection()).detail,
        isNot(contains('A model you import')),
      );
    });
  });
}
