import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/features/settings/settings_screen.dart';
import 'package:memora/src/routing/router.dart';
import 'package:memora_core/memora_core.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('shows progress, the active item and the waiting order', (
    tester,
  ) async {
    await pumpApp(tester, initialLocation: Routes.queue);

    expect(find.text('11'), findsOneWidget);
    expect(find.text('OF 17 UNDERSTOOD'), findsOneWidget);
    expect(
      find.text(
        'Paused until 01:00 tonight. 5 images waiting, one at a time, '
        'oldest first.',
      ),
      findsOneWidget,
    );

    expect(find.text('Grocery receipt, monthly run'), findsOneWidget);
    expect(find.text('PROCESSING · VISION'), findsOneWidget);
    expect(find.text('QUEUED · NEXT'), findsOneWidget);
    expect(find.text('QUEUED · 3RD'), findsOneWidget);
    expect(find.text('FAILED · PROVIDER TIMEOUT'), findsOneWidget);
  });

  testWidgets('retry puts a failed memory back in the queue', (tester) async {
    final services = await pumpApp(tester, initialLocation: Routes.queue);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(services.db.memories['m7']!.status, ProcessingStatus.captured);
    expect(services.scheduler.refreshCalls, greaterThan(0));
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('process now asks the scheduler to run the queue', (
    tester,
  ) async {
    final services = await pumpApp(tester, initialLocation: Routes.queue);

    await tester.tap(find.text('Process now'));
    await tester.pumpAndSettle();

    expect(services.scheduler.processNowCalls, 1);
    expect(find.text('Pause queue'), findsOneWidget);
  });

  testWidgets('pausing the queue changes the status copy', (tester) async {
    final services = await pumpApp(tester, initialLocation: Routes.queue);
    await tester.tap(find.text('Process now'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pause queue'));
    await tester.pumpAndSettle();

    expect((await services.scheduler.policy()).paused, isTrue);
    expect(
      find.text(
        'Queue paused. Added images stay browsable; nothing is sent until '
        'you resume.',
      ),
      findsOneWidget,
    );
    expect(find.text('Resume queue'), findsOneWidget);
  });

  testWidgets('a blocked queue explains itself and links to settings', (
    tester,
  ) async {
    final services = demoServices();
    final settings = await services.aiSettings.load();
    await services.aiSettings.save(settings.copyWith(localOnly: true));
    await pumpApp(tester, services: services, initialLocation: Routes.queue);

    expect(
      find.textContaining('Local-only mode blocks NVIDIA'),
      findsOneWidget,
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
