import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/features/home/category_filter.dart';
import 'package:memora/src/features/home/home_screen.dart';
import 'package:memora/src/services/app_services.dart';
import 'package:memora/src/state/queue.dart';
import 'package:memora/src/state/ui_state.dart';
import 'package:memora/src/widgets/chip_bar.dart';
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

  group('the category row', () {
    testWidgets('never grows past All, two chips and the button', (
      tester,
    ) async {
      await pumpApp(tester);

      // The whole point: thirty categories must not make this row scroll.
      expect(
        find.byType(SelectChip),
        findsNWidgets(CategoryFilter.visibleChips + 1),
      );
      expect(find.bySemanticsLabel('All categories'), findsOneWidget);
    });

    testWidgets('the button opens a picker that can be searched', (
      tester,
    ) async {
      await pumpApp(tester);

      await tester.tap(find.bySemanticsLabel('All categories'));
      await tester.pumpAndSettle();

      expect(find.text('CATEGORIES'), findsOneWidget);
      final before = find.byType(TextField);
      expect(before, findsOneWidget);
      expect(find.text('Bills'), findsWidgets);

      await tester.enterText(before, 'shop');
      await tester.pumpAndSettle();

      expect(find.text('Shopping'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('Bills'),
        ),
        findsNothing,
      );

      await tester.enterText(before, 'nothing like this');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Nothing called "nothing like this"'),
        findsOneWidget,
      );
    });

    testWidgets('two categories picked shows both, not neither', (
      tester,
    ) async {
      await pumpApp(tester);

      await tester.tap(find.bySemanticsLabel('All categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Bills, \d+ memories$')));
      await tester.tap(
        find.bySemanticsLabel(RegExp(r'^Shopping, \d+ memories$')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Show 2 categories'), findsOneWidget);
      await tester.tap(find.text('Show 2 categories'));
      await tester.pumpAndSettle();

      // A union. Picking two groups is not an impossible intersection.
      expect(
        find.text('Reliance electricity bill for September 2026'),
        findsOneWidget,
      );
      expect(
        find.text('MacBook Air M4 vs ThinkPad X1 comparison'),
        findsOneWidget,
      );
      // Two picked fit in two chips, so there is nothing left to count.
      expect(find.bySemanticsLabel('All categories'), findsOneWidget);
    });

    testWidgets('All clears a selection made in the picker', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.bySemanticsLabel('All categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Bills, \d+ memories$')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Show '));
      await tester.pumpAndSettle();

      expect(
        find.text('MacBook Air M4 vs ThinkPad X1 comparison'),
        findsNothing,
      );

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      expect(
        find.text('MacBook Air M4 vs ThinkPad X1 comparison'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('All categories'), findsOneWidget);
    });

    testWidgets('Clear empties the picker without leaving it', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.bySemanticsLabel('All categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Bills, \d+ memories$')));
      await tester.pumpAndSettle();
      expect(find.text('Clear'), findsOneWidget);

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(find.text('Show everything'), findsOneWidget);
      expect(find.text('Clear'), findsNothing);
    });
  });

  group('the chip row rule', () {
    // The case this whole row exists for.
    final thirty = [
      allCategoriesLabel,
      for (var i = 1; i <= 30; i++) 'Category $i',
    ];

    test('with nothing picked it is All and the two most common', () {
      expect(CategoryFilter.chipsFor(thirty, const {}), [
        'All',
        'Category 1',
        'Category 2',
      ]);
      expect(
        CategoryFilter.hiddenCount(
          CategoryFilter.chipsFor(thirty, const {}),
          const {},
        ),
        0,
      );
    });

    test('a pick from the far end of the list takes a chip', () {
      final shown = CategoryFilter.chipsFor(thirty, const {'Category 28'});
      expect(shown, ['All', 'Category 28', 'Category 1']);
      expect(
        CategoryFilter.hiddenCount(shown, const {'Category 28'}),
        0,
        reason: 'it is on screen, so there is nothing to count',
      );
    });

    test('more picks than chips puts the rest on the button', () {
      const picked = {'Category 3', 'Category 9', 'Category 17', 'Category 29'};
      final shown = CategoryFilter.chipsFor(thirty, picked);

      expect(
        shown.length,
        CategoryFilter.visibleChips + 1,
        reason: 'thirty categories must not make the row any longer',
      );
      expect(shown.first, 'All');
      expect(CategoryFilter.hiddenCount(shown, picked), 2);
    });

    test('All is always first and never duplicated', () {
      for (final picked in [
        const <String>{},
        const {'Category 1'},
        const {'Category 1', 'Category 2', 'Category 3'},
      ]) {
        final shown = CategoryFilter.chipsFor(thirty, picked);
        expect(shown.first, allCategoriesLabel);
        expect(shown.where((l) => l == allCategoriesLabel).length, 1);
        expect(shown.toSet().length, shown.length, reason: 'no repeats');
      }
    });
  });

  group('HomeFilter', () {
    HomeFilter filter() {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(homeFilterProvider);
      return container.read(homeFilterProvider.notifier);
    }

    test('All in a replacement means everything, and does not throw', () {
      final home = filter();
      home.replace({'Bills', 'Travel'});
      expect(home.state, {'Bills', 'Travel'});

      // The const empty set is unmodifiable, so a cascade that lands on it
      // throws. It is only reachable through this argument.
      home.replace({allCategoriesLabel, 'Bills'});
      expect(home.state, isEmpty);
    });

    test('toggle adds and drops without disturbing the rest', () {
      final home = filter();
      home.toggle('Bills');
      home.toggle('Travel');
      expect(home.state, {'Bills', 'Travel'});

      home.toggle('Bills');
      expect(home.state, {'Travel'});

      home.toggle(allCategoriesLabel);
      expect(home.state, isEmpty);
    });

    test('select narrows to one, and All clears', () {
      final home = filter();
      home.replace({'Bills', 'Travel'});
      home.select('Work');
      expect(home.state, {'Work'});

      home.select(allCategoriesLabel);
      expect(home.state, isEmpty);
    });
  });
}
