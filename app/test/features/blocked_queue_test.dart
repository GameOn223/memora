import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/demo/demo_ai.dart';
import 'package:memora/src/demo/demo_app_services.dart';
import 'package:memora/src/features/queue/block_notice.dart';
import 'package:memora/src/features/settings/capability_screen.dart';
import 'package:memora/src/features/settings/provider_key_screen.dart';
import 'package:memora/src/features/settings/settings_screen.dart';
import 'package:memora/src/routing/router.dart';
import 'package:memora/src/widgets/memory_image.dart';
import 'package:memora_core/memora_core.dart';

import '../helpers/pump_app.dart';

/// Demo services with no model chosen for vision.
Future<DemoAppServices> _withoutVision() async {
  final services = demoServices();
  final settings = await services.aiSettings.load();
  await services.aiSettings.save(
    settings.copyWith(
      selections: {...settings.selections}..remove(Capability.vision),
    ),
  );
  return services;
}

/// Demo services whose vision provider has no API key stored.
Future<DemoAppServices> _withoutKey() async {
  final services = demoServices();
  services.secrets.values.remove(CapabilityRouter.apiKeyName('nvidia'));
  return services;
}

/// Demo services with local-only mode on, which refuses NVIDIA.
Future<DemoAppServices> _localOnly() async {
  final services = demoServices();
  final settings = await services.aiSettings.load();
  await services.aiSettings.save(settings.copyWith(localOnly: true));
  return services;
}

/// Adds the first two gallery images from the Add screen.
Future<void> _addTwoImages(WidgetTester tester) async {
  await tester.tap(find.byType(DeviceImageView).first);
  await tester.tap(find.byType(DeviceImageView).at(1));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add 2 images'));
  await tester.pumpAndSettle();
}

void main() {
  group('block notices', () {
    final registry = buildDemoRegistry();

    test('no vision provider asks for one', () {
      final notice = blockNotice(const NoVisionProvider(), providers: registry);

      expect(
        notice.sentence,
        'No vision model is selected, so nothing will be understood yet.',
      );
      expect(notice.action, 'Choose one');
      expect(notice.route, '/settings/capability/vision');
    });

    test('local-only mode names the provider it refuses', () {
      final notice = blockNotice(
        const BlockedByLocalOnly('Groq'),
        providers: registry,
      );

      expect(
        notice.sentence,
        'Local-only mode blocks Groq, so nothing is being understood.',
      );
      expect(notice.action, 'Open settings');
      expect(notice.route, Routes.settings);
    });

    test('a key problem links straight at the key screen', () {
      final notice = blockNotice(
        const ProviderConfigurationProblem('Groq', 'Add an API key for Groq'),
        providers: registry,
      );

      expect(notice.sentence, 'Add an API key for Groq.');
      expect(notice.action, 'Fix key');
      expect(notice.route, '/settings/provider/groq');
    });

    test('a provider that needs no key goes to the provider list', () {
      final notice = blockNotice(
        const ProviderConfigurationProblem(
          'On this device',
          'Download the on-device model for On this device',
        ),
        providers: registry,
      );

      expect(notice.action, 'Choose another');
      expect(notice.route, '/settings/capability/vision');
    });

    test('a message that already ends in a stop is left alone', () {
      final notice = blockNotice(
        const ProviderConfigurationProblem(
          'Groq',
          "Groq can't understand images. Choose another vision provider.",
        ),
        providers: registry,
      );

      expect(
        notice.sentence,
        "Groq can't understand images. Choose another vision provider.",
      );
    });

    // Written ahead of the RateLimited block type in memora_core. When it
    // lands, the switch in blockNotice gets its arm and this copy is already
    // in place.
    test('rate limiting says when it will try again', () {
      final notice = BlockNotice.rateLimited(
        'Groq',
        DateTime(2026, 9, 15, 14, 32),
      );

      expect(notice.sentence, 'Groq is rate limiting. Retrying at 14:32.');
      expect(notice.action, 'Choose another');
      expect(notice.route, '/settings/capability/vision');
    });
  });

  group('the toast after an add', () {
    testWidgets('says no vision model is selected and offers to pick one', (
      tester,
    ) async {
      await pumpApp(
        tester,
        services: await _withoutVision(),
        initialLocation: Routes.add,
      );

      await _addTwoImages(tester);

      expect(find.text('2 images added'), findsOneWidget);
      expect(
        find.text(
          'No vision model is selected, so nothing will be understood yet.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Choose one'));
      await tester.pumpAndSettle();
      expect(find.byType(CapabilityScreen), findsOneWidget);
    });

    testWidgets('says the key is missing and offers to fix it', (tester) async {
      await pumpApp(
        tester,
        services: await _withoutKey(),
        initialLocation: Routes.add,
      );

      await _addTwoImages(tester);

      expect(find.text('Add an API key for NVIDIA.'), findsOneWidget);

      await tester.tap(find.text('Fix key'));
      await tester.pumpAndSettle();
      expect(find.byType(ProviderKeyScreen), findsOneWidget);
    });

    testWidgets('says local-only mode is in the way', (tester) async {
      await pumpApp(
        tester,
        services: await _localOnly(),
        initialLocation: Routes.add,
      );

      await _addTwoImages(tester);

      expect(
        find.text(
          'Local-only mode blocks NVIDIA, so nothing is being understood.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('keeps the usual copy when nothing is blocked', (tester) async {
      await pumpApp(tester, initialLocation: Routes.add);

      await _addTwoImages(tester);

      expect(find.text('2 images added'), findsOneWidget);
      expect(find.text('Queue'), findsOneWidget);
      expect(
        find.textContaining('Filed by the date each image was taken.'),
        findsOneWidget,
      );
    });
  });

  group('the queue banner', () {
    testWidgets('asks for a vision model when none is selected', (
      tester,
    ) async {
      await pumpApp(
        tester,
        services: await _withoutVision(),
        initialLocation: Routes.queue,
      );

      expect(
        find.text(
          'No vision model is selected, so nothing will be understood yet.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Choose one'));
      await tester.pumpAndSettle();
      expect(find.byType(CapabilityScreen), findsOneWidget);
    });

    testWidgets('sends a missing key to the key screen', (tester) async {
      await pumpApp(
        tester,
        services: await _withoutKey(),
        initialLocation: Routes.queue,
      );

      expect(find.text('Add an API key for NVIDIA.'), findsOneWidget);

      await tester.tap(find.text('Fix key'));
      await tester.pumpAndSettle();
      expect(find.byType(ProviderKeyScreen), findsOneWidget);
    });
  });
}
