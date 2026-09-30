import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/features/detail/detail_screen.dart';
import 'package:memora/src/routing/router.dart';

import '../helpers/pump_app.dart';

Future<void> _scrollToTop(WidgetTester tester) async {
  final list = find.byType(ListView).first;
  for (var i = 0; i < 12; i++) {
    await tester.drag(list, const Offset(0, 400));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens the latest conversation with a strip of sources', (
    tester,
  ) async {
    await pumpApp(tester, initialLocation: Routes.ask);
    await _scrollToTop(tester);

    expect(find.text('Ask Memora'), findsOneWidget);
    expect(find.text('GROQ · LLAMA-3.3-70B'), findsOneWidget);
    expect(find.text('show me all my reliance bills'), findsOneWidget);
    expect(
      find.textContaining('I found 8 Reliance electricity bills'),
      findsOneWidget,
    );
    expect(find.text('8 MEMORIES · ENTITY + SEMANTIC'), findsOneWidget);
    expect(find.text('₹2,103'), findsWidgets);
    expect(find.text('AUG 2026'), findsWidgets);
  });

  testWidgets('an aggregate answer uses the table layout and a headline', (
    tester,
  ) async {
    await pumpApp(tester, initialLocation: Routes.ask);

    expect(find.text('which one was highest?'), findsOneWidget);
    expect(find.text('MONTH'), findsOneWidget);
    expect(find.text('AMOUNT'), findsOneWidget);
    expect(find.text('VERIFIED AGAINST THE ORIGINAL IMAGE'), findsOneWidget);
    expect(find.text('Aug 2026'), findsOneWidget);
  });

  testWidgets('How this was found lists the tools that ran', (tester) async {
    await pumpApp(tester, initialLocation: Routes.ask);

    await _scrollToTop(tester);
    expect(
      find.text('search_by_entity(value: "Reliance", type: "company")'),
      findsNothing,
    );
    await tester.tap(find.text('HOW THIS WAS FOUND').first);
    await tester.pumpAndSettle();
    expect(
      find.text('search_by_entity(value: "Reliance", type: "company")'),
      findsOneWidget,
    );
  });

  testWidgets('a source opens the memory it came from', (tester) async {
    await pumpApp(tester, initialLocation: Routes.ask);

    await _scrollToTop(tester);
    await tester.tap(find.text('₹2,103').first);
    await tester.pumpAndSettle();
    expect(find.byType(DetailScreen), findsOneWidget);
  });

  testWidgets('asking shows the thinking row and then the answer', (
    tester,
  ) async {
    final services = await pumpApp(tester, initialLocation: Routes.ask);

    await tester.enterText(find.byType(TextField), 'which one was highest?');
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pump();
    await tester.pump();
    expect(find.text('SEARCHING 17 MEMORIES'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(services.chat.asked, ['which one was highest?']);
    expect(find.textContaining('The highest was August 2026'), findsWidgets);
  });

  testWidgets('a failed turn can be retried', (tester) async {
    final services = await pumpApp(tester, initialLocation: Routes.ask);
    services.chat.failNextAsk = true;

    await tester.enterText(find.byType(TextField), 'how much did I spend?');
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Groq did not respond. Try again.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Groq did not respond. Try again.'), findsNothing);
    expect(services.chat.asked.length, 2);
    // The question is only shown once, even though it was asked twice.
    expect(find.text('how much did I spend?'), findsOneWidget);
  });

  testWidgets('the history sheet starts a new conversation', (tester) async {
    await pumpApp(tester, initialLocation: Routes.ask);

    await tester.tap(find.bySemanticsLabel('Conversations'));
    await tester.pumpAndSettle();
    expect(find.text('CONVERSATIONS'), findsOneWidget);

    await tester.tap(find.text('New conversation'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('I found 8 Reliance electricity bills'),
      findsNothing,
    );
    expect(find.text('Ask about anything you saved.'), findsOneWidget);
  });
}
