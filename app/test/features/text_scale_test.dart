import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/routing/router.dart';

import '../helpers/pump_app.dart';

/// Large text is a common Android setting, so every screen has to survive
/// it without overflowing. An overflow fails the test on its own.
void main() {
  for (final scale in [1.3, 2.0]) {
    testWidgets('screens hold together at ${scale}x text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final services = demoServices();
      for (final location in [
        Routes.home,
        Routes.ask,
        Routes.queue,
        Routes.browser,
        Routes.settings,
        '/memory/m9',
      ]) {
        await pumpApp(tester, services: services, initialLocation: location);
        expect(tester.takeException(), isNull, reason: location);
      }
    });
  }

  testWidgets('the conversation drawer holds together at 2x text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpApp(tester, initialLocation: Routes.ask);
    await tester.tap(find.bySemanticsLabel('Conversations'));
    await tester.pumpAndSettle();

    expect(find.text('CONVERSATIONS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the composer grows with the text scale', (tester) async {
    await pumpApp(tester, initialLocation: Routes.ask);
    final normal = tester.getSize(find.byType(TextField)).height;

    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, initialLocation: Routes.ask);
    final large = tester.getSize(find.byType(TextField)).height;

    expect(large, greaterThan(normal));
    expect(tester.takeException(), isNull);
  });
}
