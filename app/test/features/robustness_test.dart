import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/features/detail/detail_screen.dart';
import 'package:memora/src/features/home/home_screen.dart';
import 'package:memora/src/routing/router.dart';
import 'package:memora/src/services/app_services.dart';
import 'package:memora/src/state/ui_state.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('the toast goes away even while the data version ticks', (
    tester,
  ) async {
    final services = await pumpApp(
      tester,
      // Polling on, as it is in the running app.
      pollInterval: const Duration(milliseconds: 200),
    );
    ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
        .read(addedToastProvider.notifier)
        .show(const AddImagesResult(added: 3, duplicates: 0, failed: 0));
    await tester.pump();
    expect(find.text('3 images added'), findsOneWidget);

    // Something writes every second, so every poll sees a new version.
    for (var i = 0; i < 6; i++) {
      services.db.touch();
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();

    expect(find.text('3 images added'), findsNothing);
  });

  testWidgets('a link to a memory that is gone says so', (tester) async {
    await pumpApp(tester, initialLocation: '/memory/does-not-exist');

    expect(find.byType(DetailScreen), findsOneWidget);
    expect(find.text('That memory is gone.'), findsOneWidget);

    await tester.tap(find.text('Back to memories'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('a capability opened from a link keeps the saved choice', (
    tester,
  ) async {
    await pumpApp(tester, initialLocation: '/settings/capability/vision');

    expect(find.text('Vision'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'nemotron-vl-3b',
    );
    expect(find.text('SELECTED'), findsOneWidget);
  });

  testWidgets('tapping send twice starts one turn, not two', (tester) async {
    final services = await pumpApp(tester, initialLocation: Routes.ask);
    final before = services.db.conversations.length;

    await tester.tap(find.bySemanticsLabel('Conversations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New conversation'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'how much did I spend?');
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pumpAndSettle();

    expect(services.chat.asked, ['how much did I spend?']);
    expect(services.db.conversations.length, before + 1);
  });

  testWidgets('a refused send keeps what was typed', (tester) async {
    final services = await pumpApp(tester, initialLocation: Routes.ask);
    services.chat.failNextAsk = true;

    await tester.enterText(find.byType(TextField), 'first question');
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pump();

    // While the answer is on its way, a second question is refused and the
    // text stays in the box.
    await tester.enterText(find.byType(TextField), 'second question');
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'second question',
    );

    await tester.pumpAndSettle();
    expect(services.chat.asked, ['first question']);
  });
}
