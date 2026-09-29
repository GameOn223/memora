import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/features/home/home_screen.dart';
import 'package:memora/src/routing/router.dart';
import 'package:memora/src/services/app_services.dart';
import 'package:memora/src/widgets/memory_image.dart';
import 'package:memora_core/memora_core.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('picking images adds them and returns home with a toast', (
    tester,
  ) async {
    final services = await pumpApp(tester, initialLocation: Routes.add);

    expect(find.text('Add from gallery'), findsOneWidget);
    expect(find.text('Select images to add'), findsOneWidget);

    await tester.tap(find.byType(BytesImageView).first);
    await tester.tap(find.byType(BytesImageView).at(1));
    await tester.pumpAndSettle();

    expect(find.text('Add 2 images'), findsOneWidget);
    await tester.tap(find.text('Add 2 images'));
    await tester.pumpAndSettle();

    expect(services.gallery.addCalls.single.length, 2);
    expect(services.scheduler.refreshCalls, greaterThan(0));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('2 images added'), findsOneWidget);
  });

  testWidgets('select all ticks every image and clears again', (tester) async {
    await pumpApp(tester, initialLocation: Routes.add);

    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('Add 12 images'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Select images to add'), findsOneWidget);
  });

  testWidgets('the overnight card follows the queue policy', (tester) async {
    final services = await pumpApp(tester, initialLocation: Routes.add);

    expect(find.text('Queued for tonight, while charging'), findsOneWidget);
    await tester.tap(find.text('Queued for tonight, while charging'));
    await tester.pumpAndSettle();

    expect((await services.scheduler.policy()).mode, QueueMode.immediate);
    expect(find.text('Process now, as you add them'), findsOneWidget);
  });

  testWidgets('without gallery access it offers the system picker', (
    tester,
  ) async {
    final services = await pumpApp(
      tester,
      services: demoServices(galleryAccess: GalleryAccess.denied),
      initialLocation: Routes.add,
    );

    expect(find.textContaining('Memora needs your permission'), findsOneWidget);
    expect(find.text('Allow access'), findsOneWidget);

    await tester.tap(find.text('Pick with system picker'));
    await tester.pumpAndSettle();

    expect(services.gallery.addCalls.single.length, 2);
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
