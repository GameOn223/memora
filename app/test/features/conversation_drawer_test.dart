import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/demo/demo_app_services.dart';
import 'package:memora/src/features/chat/conversation_drawer.dart';
import 'package:memora/src/routing/router.dart';

import '../helpers/pump_app.dart';

/// Two more conversations behind the one the demo seeds, both older, so the
/// seeded conversation stays the one Ask opens with.
Future<void> _seedMore(DemoAppServices services) async {
  await services.conversations.createConversation(
    'c2',
    'flight to goa',
    testNow.subtract(const Duration(days: 1)),
  );
  await services.conversations.createConversation(
    'c3',
    'laptop shortlist',
    testNow.subtract(const Duration(days: 3)),
  );
}

Future<DemoAppServices> _openDrawer(
  WidgetTester tester, {
  DemoAppServices? services,
}) async {
  final demo = await pumpApp(
    tester,
    services: services,
    initialLocation: Routes.ask,
  );
  await tester.tap(find.bySemanticsLabel('Conversations'));
  await tester.pumpAndSettle();
  return demo;
}

/// Opens the overflow menu on the row called [title].
Future<void> _openRowMenu(WidgetTester tester, String title) async {
  await tester.tap(find.bySemanticsLabel('More for $title'));
  await tester.pumpAndSettle();
}

/// Vertical order of the given row titles as the drawer lays them out.
List<String> _rowOrder(WidgetTester tester, List<String> titles) {
  final placed = [
    for (final title in titles) (title, tester.getTopLeft(find.text(title)).dy),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final row in placed) row.$1];
}

void main() {
  testWidgets('drawer text inherits a real style, not the fallback', (
    tester,
  ) async {
    await _openDrawer(tester);

    // A route has no Material above it unless something provides one, and
    // text without one falls back to the engine default: yellow, double
    // underlined. It looks fine in a test and broken on a phone, so pin the
    // ancestor and the resulting style here.
    expect(
      find.ancestor(
        of: find.text('New conversation'),
        matching: find.byType(Material),
      ),
      findsWidgets,
    );
    final style = DefaultTextStyle.of(
      tester.element(find.text('New conversation')),
    ).style;
    expect(style.decoration ?? TextDecoration.none, TextDecoration.none);
  });

  testWidgets('lists conversations, marks the current one and dates them', (
    tester,
  ) async {
    final services = demoServices();
    await _seedMore(services);
    await _openDrawer(tester, services: services);

    expect(find.text('CONVERSATIONS'), findsOneWidget);
    expect(find.text('New conversation'), findsOneWidget);
    expect(
      _rowOrder(tester, [
        'show me all my reliance bills',
        'flight to goa',
        'laptop shortlist',
      ]),
      ['show me all my reliance bills', 'flight to goa', 'laptop shortlist'],
    );
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'show me all my reliance bills, open, last used today',
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping a conversation opens it', (tester) async {
    final services = demoServices();
    await _seedMore(services);
    await _openDrawer(tester, services: services);

    await tester.tap(find.text('flight to goa'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('I found 8 Reliance electricity bills'),
      findsNothing,
    );
    expect(find.text('Ask about anything you saved.'), findsOneWidget);
  });

  testWidgets('the row menu opens beside the dots that were tapped', (
    tester,
  ) async {
    await _openDrawer(tester);
    const title = 'show me all my reliance bills';
    final dots = tester.getRect(find.bySemanticsLabel('More for $title'));
    await _openRowMenu(tester, title);
    final rename = tester.getRect(find.text('Rename'));

    // showMenu was given the row, which is as wide as the drawer, so it read
    // the row's left edge as the anchor and opened the menu against the left
    // edge of the screen instead.
    expect(
      rename.center.dx,
      greaterThan(dots.center.dx - 120),
      reason: 'the menu belongs under the dots, not off at the far left',
    );
    expect(
      rename.right,
      lessThan(ConversationDrawer.maxWidth),
      reason: 'and it still has to fit inside the drawer',
    );
  });

  testWidgets('pinning moves a conversation above the rest', (tester) async {
    final services = demoServices();
    await _seedMore(services);
    await _openDrawer(tester, services: services);

    await _openRowMenu(tester, 'laptop shortlist');
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();

    expect(services.db.conversations['c3']!.pinned, isTrue);
    expect(
      _rowOrder(tester, [
        'laptop shortlist',
        'show me all my reliance bills',
        'flight to goa',
      ]),
      ['laptop shortlist', 'show me all my reliance bills', 'flight to goa'],
    );

    await _openRowMenu(tester, 'laptop shortlist');
    await tester.tap(find.text('Unpin'));
    await tester.pumpAndSettle();

    expect(services.db.conversations['c3']!.pinned, isFalse);
    expect(
      _rowOrder(tester, ['show me all my reliance bills', 'laptop shortlist']),
      ['show me all my reliance bills', 'laptop shortlist'],
    );
  });

  testWidgets('rename opens a dialog seeded with the title and saves it', (
    tester,
  ) async {
    final services = demoServices();
    await _seedMore(services);
    await _openDrawer(tester, services: services);

    await _openRowMenu(tester, 'flight to goa');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(find.text('Rename conversation'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      'flight to goa',
    );

    await tester.enterText(find.byType(TextField).last, 'goa trip');
    await tester.tap(find.widgetWithText(TextButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(services.db.conversations['c2']!.title, 'goa trip');
    expect(find.text('goa trip'), findsOneWidget);
    expect(find.text('flight to goa'), findsNothing);
  });

  testWidgets('rename can be cancelled and keeps the old title', (
    tester,
  ) async {
    final services = demoServices();
    await _seedMore(services);
    await _openDrawer(tester, services: services);

    await _openRowMenu(tester, 'flight to goa');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'goa trip');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(services.db.conversations['c2']!.title, 'flight to goa');
    expect(find.text('flight to goa'), findsOneWidget);
  });

  testWidgets('delete asks first, says the messages go, then removes it', (
    tester,
  ) async {
    final services = demoServices();
    await _seedMore(services);
    await _openDrawer(tester, services: services);

    await _openRowMenu(tester, 'flight to goa');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete this conversation?'), findsOneWidget);
    expect(find.textContaining('Its messages go with it'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(services.db.conversations.containsKey('c2'), isTrue);

    await _openRowMenu(tester, 'flight to goa');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(services.db.conversations.containsKey('c2'), isFalse);
    expect(find.text('flight to goa'), findsNothing);
  });

  testWidgets('deleting the conversation you are in starts a fresh one', (
    tester,
  ) async {
    final services = demoServices();
    await _seedMore(services);
    await _openDrawer(tester, services: services);

    await _openRowMenu(tester, 'show me all my reliance bills');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(services.db.conversations.containsKey('c1'), isFalse);
    expect(
      find.textContaining('I found 8 Reliance electricity bills'),
      findsNothing,
    );
    expect(find.text('Ask about anything you saved.'), findsOneWidget);
  });

  testWidgets('with nothing asked yet it explains the empty drawer', (
    tester,
  ) async {
    await _openDrawer(tester, services: demoServices(seed: false));

    expect(find.text('No conversations yet.'), findsOneWidget);
    expect(find.text('New conversation'), findsOneWidget);
  });
}
