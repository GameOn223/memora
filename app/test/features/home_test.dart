import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/features/home/home_screen.dart';
import 'package:memora/src/services/app_services.dart';
import 'package:memora/src/state/queue.dart';
import 'package:memora/src/state/ui_state.dart';
import 'package:memora/src/widgets/memory_tile.dart';
import 'package:memora_core/memora_core.dart';

import '../helpers/pump_app.dart';

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));

void main() {
  testWidgets('groups memories under the date each image was taken', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(find.text('2 images'), findsWidgets);
    expect(find.text('3 images'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('12 SEPTEMBER 2026'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('12 SEPTEMBER 2026'), findsOneWidget);
  });

  testWidgets('the density toggle changes the grid and is remembered', (
    tester,
  ) async {
    final services = await pumpApp(tester);

    expect(
      find.text('Reliance electricity bill for September 2026'),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel('Dense grid, 8 columns'));
    await tester.pumpAndSettle();

    expect(
      find.text('Reliance electricity bill for September 2026'),
      findsNothing,
    );
    expect(await services.preferences.gridColumns(), 8);
    expect(tester.widget<MemoryTile>(find.byType(MemoryTile).first).columns, 8);
  });

  testWidgets('filter chips narrow the grid to one group of categories', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(
      find.text('MacBook Air M4 vs ThinkPad X1 comparison'),
      findsOneWidget,
    );

    await tester.tap(find.text('Bills'));
    await tester.pumpAndSettle();

    expect(find.text('MacBook Air M4 vs ThinkPad X1 comparison'), findsNothing);
    expect(
      find.text('Reliance electricity bill for September 2026'),
      findsOneWidget,
    );
  });

  testWidgets('the added toast explains overnight processing', (tester) async {
    await pumpApp(tester);
    _container(tester)
        .read(addedToastProvider.notifier)
        .show(const AddImagesResult(added: 7, duplicates: 0, failed: 0));
    await tester.pump();

    expect(find.text('7 images added'), findsOneWidget);
    expect(
      find.text(
        'Filed by the date each image was taken. Processing starts at 01:00 '
        'while charging.',
      ),
      findsOneWidget,
    );
    expect(find.text('ADDED'), findsOneWidget);
    expect(find.text('UNDERSTOOD'), findsOneWidget);
  });

  testWidgets('the added toast reports duplicates and immediate processing', (
    tester,
  ) async {
    final services = await pumpApp(tester);
    await services.scheduler.setPolicy(
      const QueuePolicy(mode: QueueMode.immediate),
    );
    final container = _container(tester);
    container.invalidate(queuePolicyProvider);
    container
        .read(addedToastProvider.notifier)
        .show(const AddImagesResult(added: 1, duplicates: 3, failed: 0));
    await tester.pumpAndSettle();

    expect(find.text('1 image added'), findsOneWidget);
    expect(
      find.text(
        'Filed by the date each image was taken. Processing one at a time '
        'now. 3 were already in Memora.',
      ),
      findsOneWidget,
    );
  });
}
