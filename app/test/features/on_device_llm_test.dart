import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/demo/demo_app_services.dart';
import 'package:memora/src/features/settings/on_device_llm.dart';
import 'package:memora/src/features/settings/settings_screen.dart';
import 'package:memora/src/routing/router.dart';
import 'package:memora/src/state/local_llm.dart';
import 'package:memora_core/memora_core.dart';

import '../helpers/pump_app.dart';

/// Demo services whose import and generation finish straight away.
DemoAppServices llmServices() {
  final services = demoServices();
  services.llmFiles.step = Duration.zero;
  services.llmRuntime.step = Duration.zero;
  return services;
}

Future<void> openModels(WidgetTester tester) =>
    scrollTo(tester, find.text('Gemma 3 1B'));

/// The import bar. Nothing else on this screen is downloading in the demo.
final barFinder = find.byType(LinearProgressIndicator);

/// Scoped to the generative models section, because the embedding model has
/// a Download of its own further up the screen.
Finder inSection(Finder matching) =>
    find.descendant(of: find.byType(OnDeviceLlmSection), matching: matching);

void main() {
  testWidgets('lists what each model adds and what the phone can hold', (
    tester,
  ) async {
    await pumpApp(
      tester,
      services: llmServices(),
      initialLocation: Routes.settings,
    );

    await openModels(tester);

    expect(find.text('CHAT AND VISION ON THIS DEVICE'), findsOneWidget);
    expect(find.text('550 MB · THIS PHONE CAN RUN IT'), findsOneWidget);
    expect(
      find.text('Answers questions about your memories in its own words.'),
      findsOneWidget,
    );
    expect(find.text('IMPORT A MODEL FILE'), findsOneWidget);

    // The demo phone has 3 GB of RAM, so the larger model cannot run.
    expect(find.text('Gemma 3n E2B'), findsOneWidget);
    expect(
      find.text('3.0 GB · NOT ENOUGH MEMORY ON THIS PHONE'),
      findsOneWidget,
    );
    expect(find.text('WILL NOT RUN HERE'), findsOneWidget);
    expect(
      find.textContaining('this phone does not have it'),
      findsOneWidget,
      reason:
          'a phone that cannot run a 3 GB model should be told so '
          'before the download, not after',
    );
    expect(
      find.textContaining('It answers more slowly than a cloud model'),
      findsOneWidget,
    );
    expect(find.textContaining('Gemma Terms of Use'), findsOneWidget);
  });

  testWidgets('imports a model file and offers to delete it', (tester) async {
    final services = await pumpApp(
      tester,
      services: llmServices(),
      initialLocation: Routes.settings,
    );

    await openModels(tester);
    await tester.tap(find.text('IMPORT A MODEL FILE'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(services.llmFiles.models.single.modelId, 'gemma-3-1b-it-int4');
    expect(
      services.llmFiles.models.single.relativePath,
      'models/gemma-3-1b-it-int4.task',
    );
    await openModels(tester);
    expect(find.text('550 MB · INSTALLED'), findsOneWidget);
    expect(find.text('REMOVE'), findsOneWidget);

    await tester.tap(find.text('REMOVE'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(services.llmFiles.models, isEmpty);
    await openModels(tester);
    expect(find.text('IMPORT A MODEL FILE'), findsOneWidget);
  });

  testWidgets('the bar waits with no end, then follows the copy', (
    tester,
  ) async {
    final services = demoServices();
    // Slow enough to see the states a real import passes through.
    services.llmFiles.step = const Duration(milliseconds: 100);
    services.llmRuntime.step = Duration.zero;
    await pumpApp(tester, services: services, initialLocation: Routes.settings);

    await openModels(tester);
    await tester.tap(find.text('IMPORT A MODEL FILE'));
    await tester.pump();

    expect(
      tester.widget<LinearProgressIndicator>(barFinder).value,
      isNull,
      reason:
          'the picker is still open and nothing has been copied, so a bar '
          'with no end is the only honest one',
    );

    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.widget<LinearProgressIndicator>(barFinder).value, 0.25);

    for (var step = 0; step < 4; step++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(barFinder, findsNothing);
    await openModels(tester);
    expect(find.text('REMOVE'), findsOneWidget);
  });

  testWidgets('says what to do about the wrong kind of file', (tester) async {
    final services = llmServices();
    services.llmFiles.refuseNext = ModelImportRefusal.wrongFileType;
    await pumpApp(tester, services: services, initialLocation: Routes.settings);

    await openModels(tester);
    await tester.tap(find.text('IMPORT A MODEL FILE'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    await openModels(tester);
    expect(
      find.textContaining('"gemma-3-1b-it.gguf" is not a .task model'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Download the .task file from the Hugging Face'),
      findsOneWidget,
    );
    expect(services.llmFiles.models, isEmpty);
  });

  testWidgets('a cancelled picker leaves everything alone', (tester) async {
    final services = llmServices();
    services.llmFiles.cancelNext = true;
    await pumpApp(tester, services: services, initialLocation: Routes.settings);

    await openModels(tester);
    await tester.tap(find.text('IMPORT A MODEL FILE'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    await openModels(tester);
    expect(services.llmFiles.models, isEmpty);
    expect(find.text('IMPORT A MODEL FILE'), findsOneWidget);
    expect(find.textContaining('is not a .task model'), findsNothing);
  });

  group('local-only mode', () {
    Future<DemoAppServices> withLocalChat(
      WidgetTester tester, {
      required bool installed,
    }) async {
      final services = llmServices();
      if (installed) {
        services.llmFiles.models.add(
          const InstalledLlmModel(
            modelId: 'gemma-3-1b-it-int4',
            relativePath: 'models/gemma-3-1b-it-int4.task',
            sizeBytes: 550 * 1024 * 1024,
          ),
        );
      }
      final settings = await services.aiSettings.load();
      await services.aiSettings.save(
        settings.copyWith(
          localOnly: true,
          selections: {
            ...settings.selections,
            Capability.chat: const CapabilitySelection(
              'local',
              'gemma-3-1b-it-int4',
            ),
            Capability.vision: const CapabilitySelection('local', 'ocr-rules'),
          },
        ),
      );
      await pumpApp(
        tester,
        services: services,
        initialLocation: Routes.settings,
      );
      return services;
    }

    testWidgets('an installed model answers chat on the phone', (tester) async {
      await withLocalChat(tester, installed: true);

      expect(
        find.textContaining('Vision, chat and search all run here'),
        findsOneWidget,
      );
      expect(find.text('UNAVAILABLE IN LOCAL-ONLY MODE'), findsNothing);
      expect(find.text('GEMMA-3-1B-IT-INT4 · ON DEVICE'), findsOneWidget);
    });

    testWidgets('without the file, chat is unavailable and says why', (
      tester,
    ) async {
      await withLocalChat(tester, installed: false);

      expect(find.textContaining('Ask answers from search'), findsOneWidget);
      expect(
        find.text('GEMMA-3-1B-IT-INT4 · MODEL NOT ON THIS PHONE'),
        findsOneWidget,
      );
    });
  });

  testWidgets('the chat header names the on-device model', (tester) async {
    final services = llmServices();
    services.llmFiles.models.add(
      const InstalledLlmModel(
        modelId: 'gemma-3-1b-it-int4',
        relativePath: 'models/gemma-3-1b-it-int4.task',
        sizeBytes: 550 * 1024 * 1024,
      ),
    );
    final settings = await services.aiSettings.load();
    await services.aiSettings.save(
      settings.copyWith(
        localOnly: true,
        selections: {
          ...settings.selections,
          Capability.chat: const CapabilitySelection(
            'local',
            'gemma-3-1b-it-int4',
          ),
        },
      ),
    );

    await pumpApp(tester, services: services, initialLocation: Routes.ask);

    expect(find.text('SEARCH ONLY · NO CHAT MODEL'), findsNothing);
    expect(find.text('ON THIS DEVICE · GEMMA-3-1B-IT-INT4'), findsOneWidget);
  });

  group('copy', () {
    test('local-only mode only promises chat when it runs here', () {
      const onDevice = ProviderDescriptor(
        id: 'local',
        displayName: 'On this device',
        location: ProviderLocation.onDevice,
        capabilities: {Capability.chat},
      );
      const cloud = ProviderDescriptor(
        id: 'groq',
        displayName: 'Groq',
        location: ProviderLocation.cloud,
        capabilities: {Capability.chat},
      );

      expect(
        localOnlyBody(
          localOnly: true,
          chat: const CapabilityStatus.available(onDevice, 'gemma-3-1b'),
        ),
        contains('gemma-3-1b'),
      );
      expect(
        localOnlyBody(
          localOnly: true,
          chat: const CapabilityStatus.available(cloud, 'llama-3.3-70b'),
        ),
        contains('import a model below'),
      );
      expect(
        localOnlyBody(
          localOnly: true,
          chat: const CapabilityStatus.unavailable(
            UnavailableReason.modelNotDownloaded,
          ),
        ),
        contains('answers from search'),
      );
      expect(localOnlyBody(localOnly: false, chat: null), startsWith('Off.'));
    });

    test('a refused import says what file to look for', () {
      expect(
        LocalLlmController.refusalMessage(
          ModelImportRefusal.wrongFileType,
          modelId: 'gemma-3-1b-it-int4',
          fileName: 'model.gguf',
        ),
        '"model.gguf" is not a .task model. Download the .task file from '
        'the Hugging Face page and import that one.',
      );
      expect(
        LocalLlmController.refusalMessage(
          ModelImportRefusal.notEnoughStorage,
          modelId: 'gemma-3n-e2b-it-int4',
        ),
        contains('not enough free space for 3.0 GB'),
      );
      expect(
        LocalLlmController.refusalMessage(
          ModelImportRefusal.unreadable,
          modelId: 'gemma-3-1b-it-int4',
        ),
        contains('could not read that file'),
      );
    });
  });

  group('the access token', () {
    testWidgets('without one the row imports and the field asks for it', (
      tester,
    ) async {
      await pumpApp(
        tester,
        services: llmServices(),
        initialLocation: Routes.settings,
      );

      await openModels(tester);

      expect(find.text('IMPORT A MODEL FILE'), findsOneWidget);
      expect(inSection(find.text('DOWNLOAD')), findsNothing);
      await scrollTo(tester, find.text('HUGGING FACE TOKEN'));
      expect(find.text('HUGGING FACE TOKEN'), findsOneWidget);
      expect(
        find.textContaining('there is no link that works without one'),
        findsNothing,
        reason: 'that line is for a failed attempt, not the resting state',
      );
      expect(find.textContaining('Paste a read token below'), findsOneWidget);
    });

    testWidgets('saving a token turns the row into a download', (tester) async {
      final services = llmServices();
      await pumpApp(
        tester,
        services: services,
        initialLocation: Routes.settings,
      );

      await scrollTo(tester, find.text('HUGGING FACE TOKEN'));
      await tester.enterText(find.byType(TextField).last, 'hf_from_the_user');
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('Save token'));
      await tester.tap(find.text('Save token'));
      await tester.pumpAndSettle();

      expect(
        services.secrets.values[LocalLlmController.tokenKey],
        'hf_from_the_user',
      );
      await openModels(tester);
      expect(inSection(find.text('DOWNLOAD')), findsOneWidget);
      expect(find.text('IMPORT A MODEL FILE'), findsNothing);
      expect(
        find.textContaining('Already downloaded it?'),
        findsOneWidget,
        reason: 'importing should still be reachable, just out of the way',
      );
    });

    testWidgets('downloading hands the saved token to the fetch', (
      tester,
    ) async {
      final services = llmServices();
      services.secrets.values[LocalLlmController.tokenKey] = 'hf_saved';
      await pumpApp(
        tester,
        services: services,
        initialLocation: Routes.settings,
      );

      await openModels(tester);
      await tester.tap(inSection(find.text('DOWNLOAD')));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));

      expect(services.llmFiles.tokensSeen, ['hf_saved']);
      expect(services.llmFiles.models.single.modelId, 'gemma-3-1b-it-int4');
      await openModels(tester);
      expect(find.text('REMOVE'), findsOneWidget);
    });

    testWidgets('a token the server refuses says to check the token', (
      tester,
    ) async {
      final services = llmServices();
      services.secrets.values[LocalLlmController.tokenKey] = 'hf_wrong';
      services.llmFiles.refuseNext = ModelImportRefusal.tokenRejected;
      await pumpApp(
        tester,
        services: services,
        initialLocation: Routes.settings,
      );

      await openModels(tester);
      await tester.tap(inSection(find.text('DOWNLOAD')));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));

      await openModels(tester);
      expect(find.textContaining('would not take that token'), findsOneWidget);
      expect(services.llmFiles.models, isEmpty);
    });

    test('a model granted by hand says to request access, not to retry', () {
      // Google grants this one by hand, so a token that works elsewhere is
      // still refused here until the request goes through. Saying "try
      // again" would send someone round a loop.
      final message = LocalLlmController.refusalMessage(
        ModelImportRefusal.licenceNotAccepted,
        modelId: 'gemma-3n-e2b-it-int4',
      );
      expect(message, contains('granted by hand'));
      expect(message, contains('Request access on its page'));

      // The 1B repository grants on acceptance, so that one does say to
      // accept the licence and come back.
      final automatic = LocalLlmController.refusalMessage(
        ModelImportRefusal.licenceNotAccepted,
        modelId: 'gemma-3-1b-it-int4',
      );
      expect(automatic, contains('Gemma Terms of Use'));
      expect(automatic, contains('Accept it on the model page'));
    });
  });
}
