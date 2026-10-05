import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/features/home/home_screen.dart';
import 'package:memora/src/routing/router.dart';
import 'package:memora/src/widgets/memory_image.dart';
import 'package:memora_core/memora_core.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('a failed export says so and stays usable', (tester) async {
    final services = await pumpApp(tester, initialLocation: Routes.settings);
    services.export.failNext = true;

    await scrollTo(tester, find.text('Export all memories'));
    await tester.tap(find.text('Export all memories'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Export failed'), findsOneWidget);
    // The action is enabled again, so a second try works.
    expect(find.text('Export all memories'), findsOneWidget);
    await tester.tap(find.text('Export all memories'));
    await tester.pumpAndSettle();
    expect(services.export.exports, 2);
    expect(find.text('Export saved.'), findsOneWidget);
  });

  testWidgets('a failed reindex leaves the other actions alone', (
    tester,
  ) async {
    final services = await pumpApp(tester, initialLocation: Routes.settings);
    services.pipeline.failNext = true;

    await scrollTo(tester, find.text('Reindex embeddings'));
    await tester.tap(find.text('Reindex embeddings'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Reindexing failed'), findsOneWidget);
    await tester.tap(find.text('Export all memories'));
    await tester.pumpAndSettle();
    expect(services.export.exports, 1);
  });

  testWidgets('a failed model download is reported', (tester) async {
    final services = await pumpApp(tester, initialLocation: Routes.settings);
    services.localModels.failNext = true;

    await scrollTo(tester, find.text('bge-small-en v1.5'));
    await tester.tap(find.text('bge-small-en v1.5'));
    await tester.pumpAndSettle();

    expect(find.textContaining('download failed'), findsOneWidget);
  });

  testWidgets('a failed add keeps the selection and the button', (
    tester,
  ) async {
    final services = await pumpApp(tester, initialLocation: Routes.add);
    services.gallery.failNext = true;

    await tester.tap(find.byType(DeviceImageView).first);
    await tester.tap(find.byType(DeviceImageView).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add 2 images'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsNothing);
    expect(find.textContaining('could not be added'), findsOneWidget);
    // Not stuck on the busy label, so the user can try again.
    expect(find.text('Add 2 images'), findsOneWidget);

    await tester.tap(find.text('Add 2 images'));
    await tester.pumpAndSettle();
    expect(services.gallery.addCalls.length, 2);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('a gallery that cannot be read explains itself', (tester) async {
    final services = demoServices();
    services.gallery.failNext = true;
    await pumpApp(tester, services: services, initialLocation: Routes.add);

    expect(find.textContaining('could not be read'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceImageView), findsWidgets);
  });

  testWidgets('a key that cannot be saved does not look saved', (tester) async {
    final services = await pumpApp(
      tester,
      initialLocation: '/settings/provider/openai',
    );
    services.secrets.failNext = true;

    await tester.enterText(find.byType(TextField), 'sk-test-000012345678');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save key'));
    await tester.pumpAndSettle();

    expect(find.textContaining('could not be saved'), findsOneWidget);
    expect(
      await services.secrets.read(CapabilityRouter.apiKeyName('openai')),
      isNull,
    );
  });
}
