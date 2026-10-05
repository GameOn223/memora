import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/features/detail/memory_facts.dart';
import 'package:memora/src/features/queue/queue_screen.dart';
import 'package:memora/src/widgets/caps_label.dart';
import 'package:memora/src/widgets/tags.dart';
import 'package:memora_core/memora_core.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('shows the facts in the order the design lists them', (
    tester,
  ) async {
    final services = demoServices();
    await pumpApp(tester, services: services, initialLocation: '/memory/m9');

    final details = (await services.memories.getDetails('m9'))!;
    expect(factRows(details), [
      ('Amount', '₹1,690'),
      ('Company', 'Reliance'),
      ('Due date', '31 Jul 2026'),
      ('Account', '•••• 4471'),
      ('Image taken', '28 Aug 2026, 20:11'),
      ('Added to Memora', '15 Sep 2026, 09:12'),
    ]);

    expect(
      find.text('Reliance electricity bill for July 2026'),
      findsOneWidget,
    );
    expect(find.text('UTILITY_BILL'), findsOneWidget);
    expect(find.text('AI READY'), findsOneWidget);
    expect(find.text('₹1,690'), findsOneWidget);
    expect(find.text('1080 × 2400 · PNG · 412 KB'), findsOneWidget);
  });

  testWidgets('an image added later explains how it was filed', (tester) async {
    await pumpApp(tester, initialLocation: '/memory/m9');

    expect(
      find.textContaining('the date the image was taken', findRichText: true),
      findsOneWidget,
    );
    await scrollTo(tester, find.text('VISION · NVIDIA / NEMOTRON-VL-3B'));
    expect(find.text('EMBEDDING · LOCAL / BGE-SMALL-EN-V1.5'), findsOneWidget);
    expect(find.text('USED IN 3 CONVERSATIONS'), findsNothing);
    expect(find.text('Used in 3 conversations'), findsOneWidget);
  });

  testWidgets('a failed memory shows the reason and can be retried', (
    tester,
  ) async {
    final services = await pumpApp(tester, initialLocation: '/memory/m7');

    expect(find.text('Could not process: provider timeout.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(services.db.memories['m7']!.status, ProcessingStatus.captured);
    expect(services.scheduler.refreshCalls, greaterThan(0));
    expect(find.text('IN QUEUE'), findsOneWidget);
  });

  testWidgets('reprocess sends the memory back to the queue', (tester) async {
    final services = await pumpApp(tester, initialLocation: '/memory/m6');

    await scrollTo(tester, find.text('Reprocess'));
    await tester.tap(find.text('Reprocess'));
    await tester.pumpAndSettle();

    expect(services.db.memories['m6']!.status, ProcessingStatus.reprocessing);
    expect(find.byType(QueueScreen), findsOneWidget);
  });

  testWidgets('delete asks first, then removes the memory and its files', (
    tester,
  ) async {
    final services = await pumpApp(tester, initialLocation: '/memory/m6');

    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete memory'));
    await tester.pumpAndSettle();

    expect(find.text('Delete this memory?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(services.db.memories.containsKey('m6'), isFalse);
    expect(services.db.images.containsKey('originals/m6.png'), isFalse);
  });

  testWidgets('keywords are chips under their own label, not facts rows', (
    tester,
  ) async {
    final services = demoServices();
    await pumpApp(tester, services: services, initialLocation: '/memory/m9');

    final details = (await services.memories.getDetails('m9'))!;
    expect(details.keywords, [
      'reliance',
      'electricity',
      'bill',
      'payment',
      'july',
      'due date',
    ]);
    // The table is for facts. Keywords have no row in it.
    expect(factRows(details).map((row) => row.$1), isNot(contains('Keywords')));

    await scrollTo(tester, find.text('KEYWORDS'));
    expect(find.byType(KeywordChip), findsNWidgets(details.keywords.length));
    for (final keyword in details.keywords) {
      expect(find.widgetWithText(KeywordChip, keyword), findsOneWidget);
    }

    // Every chip is the design's 26px pill, each row holds several of them,
    // and they wrap rather than running off the screen.
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final rects = [
      for (final chip in find.byType(KeywordChip).evaluate())
        tester.getRect(find.byWidget(chip.widget)),
    ];
    final rows = {for (final rect in rects) rect.top};
    expect(rows.length, greaterThan(1));
    expect(rows.length, lessThan(rects.length));
    for (final rect in rects) {
      expect(rect.height, moreOrLessEquals(26));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(width));
    }
  });

  testWidgets('pending memories keep the caps label for their state', (
    tester,
  ) async {
    await pumpApp(tester, initialLocation: '/memory/m3');

    expect(find.byType(CapsLabel), findsWidgets);
    expect(find.text('IN QUEUE'), findsOneWidget);
    expect(find.text('Reprocess'), findsNothing);
  });
}
