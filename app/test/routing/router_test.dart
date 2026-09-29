import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/features/detail/detail_screen.dart';
import 'package:memora/src/features/home/home_screen.dart';
import 'package:memora/src/features/settings/settings_screen.dart';
import 'package:memora/src/widgets/bottom_tabs.dart';
import 'package:memora/src/widgets/memory_tile.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('home shows the four tabs', (tester) async {
    await pumpApp(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(BottomTabs), findsOneWidget);
    for (final (label, _) in BottomTabs.items) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('a tile opens the memory and back returns home', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byType(MemoryTile).first);
    await tester.pumpAndSettle();

    expect(find.byType(DetailScreen), findsOneWidget);
    expect(find.byType(BottomTabs), findsNothing);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(BottomTabs), findsOneWidget);
  });

  testWidgets('tabs switch screens and system back returns to Memories', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Ask and Add run without the tab bar', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    expect(find.text('Ask Memora'), findsOneWidget);
    expect(find.byType(BottomTabs), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('demo services fill the grid with the design memories', (
    tester,
  ) async {
    final services = await pumpApp(tester);

    expect(services.db.memories.length, 17);
    expect(find.text('TODAY'), findsOneWidget);
    expect(
      find.text('Reliance electricity bill for September 2026'),
      findsOneWidget,
    );
    expect(
      find.text('MacBook Air M4 vs ThinkPad X1 comparison'),
      findsOneWidget,
    );
  });
}
