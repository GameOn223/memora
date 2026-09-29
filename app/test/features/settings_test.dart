import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/routing/router.dart';
import 'package:memora/src/services/app_services.dart';
import 'package:memora/src/state/settings.dart';
import 'package:memora_core/memora_core.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('lists capabilities, keys and storage', (tester) async {
    await pumpApp(tester, initialLocation: Routes.settings);

    expect(find.text('AI & privacy'), findsOneWidget);
    expect(find.text('Local-only mode'), findsOneWidget);
    expect(find.text('Vision'), findsOneWidget);
    expect(find.text('NEMOTRON-VL-3B'), findsOneWidget);
    expect(find.text('NVIDIA'), findsWidgets);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('BGE-SMALL-EN-V1.5 · ON DEVICE'), findsOneWidget);
    expect(find.text('LOCAL'), findsWidgets);

    await scrollTo(tester, find.text('nvapi-••••7Q2f'));
    expect(find.text('nvapi-••••7Q2f'), findsOneWidget);
    expect(find.text('gsk_Tn••••x91b'), findsOneWidget);
    expect(find.text('Not configured'), findsWidgets);
  });

  testWidgets('local-only mode marks cloud capabilities unavailable', (
    tester,
  ) async {
    final services = await pumpApp(tester, initialLocation: Routes.settings);

    await tester.tap(find.text('Local-only mode'));
    await tester.pumpAndSettle();

    expect(find.text('Turn on local-only mode?'), findsOneWidget);
    expect(
      find.textContaining('Vision (NVIDIA) and Chat (Groq)'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Turn on'));
    await tester.pumpAndSettle();

    expect((await services.aiSettings.load()).localOnly, isTrue);
    expect(find.text('UNAVAILABLE IN LOCAL-ONLY MODE'), findsNWidgets(2));
  });

  testWidgets('a cloud provider asks before it is used', (tester) async {
    final services = demoServices();
    final settings = await services.aiSettings.load();
    await services.aiSettings.save(
      settings.copyWith(acknowledgedCloudProviders: const {}),
    );
    await pumpApp(
      tester,
      services: services,
      initialLocation: '/settings/capability/chat',
    );

    await tester.tap(find.text('OpenAI'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Use OpenAI'));
    await tester.tap(find.text('Use OpenAI'));
    await tester.pumpAndSettle();

    expect(find.text('Send data to OpenAI?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Continue'));
    await tester.pumpAndSettle();

    final saved = await services.aiSettings.load();
    expect(saved.acknowledgedCloudProviders, contains('openai'));
    expect(
      saved.selections[Capability.chat],
      const CapabilitySelection('openai', 'gpt-5-mini'),
    );
  });

  testWidgets('an acknowledged provider is not asked about again', (
    tester,
  ) async {
    final services = demoServices();
    final settings = await services.aiSettings.load();
    await services.aiSettings.save(
      settings.copyWith(acknowledgedCloudProviders: const {'openai'}),
    );
    await pumpApp(
      tester,
      services: services,
      initialLocation: '/settings/capability/chat',
    );

    await tester.tap(find.text('OpenAI'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Use OpenAI'));
    await tester.tap(find.text('Use OpenAI'));
    await tester.pumpAndSettle();

    expect(find.text('Send data to OpenAI?'), findsNothing);
    expect(
      (await services.aiSettings.load())
          .selections[Capability.chat]
          ?.providerId,
      'openai',
    );
  });

  testWidgets('an API key can be saved, tested and removed', (tester) async {
    final services = await pumpApp(
      tester,
      initialLocation: '/settings/provider/openai',
    );

    await tester.enterText(find.byType(TextField), 'sk-test-000012345678');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save key'));
    await tester.pumpAndSettle();

    expect(
      await services.secrets.read(CapabilityRouter.apiKeyName('openai')),
      'sk-test-000012345678',
    );
    expect(find.text('Saved: sk-tes••••5678'), findsOneWidget);

    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Connected.'), findsOneWidget);

    await tester.tap(find.text('Remove key'));
    await tester.pumpAndSettle();
    expect(
      await services.secrets.read(CapabilityRouter.apiKeyName('openai')),
      isNull,
    );
  });

  test('keys are masked to their first six and last four characters', () {
    expect(maskApiKey('nvapi-Hk29dXz0pLq7Q2f'), 'nvapi-••••7Q2f');
    expect(maskApiKey('gsk_Tn4mW81rVx91b'), 'gsk_Tn••••x91b');
    expect(maskApiKey('short'), '••••rt');
    expect(maskApiKey(null), isNull);
  });

  testWidgets('deleting everything needs the word DELETE', (tester) async {
    final services = await pumpApp(tester, initialLocation: Routes.settings);

    await scrollTo(tester, find.text('Delete all memories'));
    await tester.tap(find.text('Delete all memories'));
    await tester.pumpAndSettle();

    expect(find.text('Delete all memories?'), findsOneWidget);
    final delete = find.widgetWithText(TextButton, 'Delete');
    expect(tester.widget<TextButton>(delete).onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'DELETE');
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(delete).onPressed, isNotNull);

    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(services.db.memories, isEmpty);
  });

  testWidgets('appearance switches the theme', (tester) async {
    final services = await pumpApp(tester, initialLocation: Routes.settings);

    await scrollTo(tester, find.text('Light'));
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(await services.preferences.theme(), ThemePreference.light);
  });
}
