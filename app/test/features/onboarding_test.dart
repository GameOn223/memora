import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/features/home/empty_state.dart';
import 'package:memora/src/features/onboarding/onboarding_screen.dart';
import 'package:memora/src/features/settings/settings_screen.dart';
import 'package:memora/src/widgets/bottom_tabs.dart';
import 'package:memora_core/memora_core.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('first launch opens onboarding', (tester) async {
    await pumpApp(
      tester,
      services: demoServices(seed: false, onboardingComplete: false),
    );

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('Your memories stay on your device.'), findsOneWidget);
    expect(
      find.textContaining('Pick images from your gallery, share them'),
      findsOneWidget,
    );
  });

  testWidgets('local-only mode selects on-device capabilities and goes home', (
    tester,
  ) async {
    final services = await pumpApp(
      tester,
      services: demoServices(seed: false, onboardingComplete: false),
    );

    await tester.tap(find.text('Start in local-only mode'));
    await tester.pumpAndSettle();

    final settings = await services.aiSettings.load();
    expect(settings.localOnly, isTrue);
    expect(
      settings.selections[Capability.vision],
      const CapabilitySelection('local', 'ocr-rules'),
    );
    expect(
      settings.selections[Capability.embeddings],
      const CapabilitySelection('local', 'bge-small-en-v1.5'),
    );
    expect(
      settings.selections[Capability.reranking],
      const CapabilitySelection('local', 'score-fusion'),
    );
    expect(settings.selections[Capability.chat], isNull);
    expect(await services.preferences.onboardingComplete(), isTrue);

    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('No memories yet.'), findsOneWidget);
    // The empty screen carries its own call to action, so no tab bar.
    expect(find.byType(BottomTabs), findsNothing);
  });

  testWidgets('choosing providers opens settings with nothing selected', (
    tester,
  ) async {
    final services = await pumpApp(
      tester,
      services: demoServices(seed: false, onboardingComplete: false),
    );

    await tester.tap(find.text('Choose AI providers instead'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(await services.preferences.onboardingComplete(), isTrue);
    final settings = await services.aiSettings.load();
    expect(settings.localOnly, isFalse);
    expect(settings.selections, isEmpty);
  });

  testWidgets('skip completes onboarding', (tester) async {
    final services = await pumpApp(
      tester,
      services: demoServices(seed: false, onboardingComplete: false),
    );

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsOneWidget);
    expect(await services.preferences.onboardingComplete(), isTrue);
  });

  testWidgets('the empty screen explains how memories are made', (
    tester,
  ) async {
    await pumpApp(tester, services: demoServices(seed: false));

    expect(
      find.textContaining('A memory exists because you chose it'),
      findsOneWidget,
    );
    expect(find.text('HOW IT WORKS'), findsOneWidget);
    expect(find.textContaining('one, or a few hundred'), findsOneWidget);
    expect(find.text('Add images from gallery'), findsOneWidget);
  });
}
