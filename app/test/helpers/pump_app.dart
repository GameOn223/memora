import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/demo/demo_app_services.dart';
import 'package:memora/src/routing/memora_app.dart';
import 'package:memora/src/services/app_services.dart';
import 'package:memora/src/state/data_version.dart';
import 'package:memora/src/state/services.dart';
import 'package:memora_core/memora_core.dart';

/// The clock every test runs against: the date the design was drawn.
final testNow = DateTime(2026, 9, 15, 10, 0);

class TestClock implements Clock {
  TestClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

/// Phone-sized surface used by tests and screenshots: 1080 x 2340 at 2.625.
const testSurface = Size(411.42857, 891.42857);

/// Builds demo services pinned to [testNow].
DemoAppServices demoServices({
  bool seed = true,
  bool onboardingComplete = true,
  GalleryAccess galleryAccess = GalleryAccess.full,
  int galleryImageCount = 12,
  Duration chatStep = const Duration(milliseconds: 50),
}) {
  return DemoAppServices(
    clock: TestClock(testNow),
    seed: seed,
    onboardingComplete: onboardingComplete,
    galleryAccess: galleryAccess,
    galleryImageCount: galleryImageCount,
    chatStep: chatStep,
  );
}

/// Pumps the whole app with demo services on a phone-sized surface.
Future<DemoAppServices> pumpApp(
  WidgetTester tester, {
  DemoAppServices? services,
  String? initialLocation,
  Brightness platformBrightness = Brightness.dark,
  List<Override> overrides = const [],
  Widget Function(Widget app)? wrap,
  Duration? pollInterval,
}) async {
  final demo = services ?? demoServices();
  tester.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 2.625
    ..padding = const FakeViewPadding(top: 63, bottom: 63)
    ..viewPadding = const FakeViewPadding(top: 63, bottom: 63);
  tester.platformDispatcher
    ..platformBrightnessTestValue = platformBrightness
    ..accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher
      ..clearPlatformBrightnessTestValue()
      ..clearAccessibilityFeaturesTestValue();
  });
  await tester.pumpWidget(
    ProviderScope(
      // Tests drive refreshes explicitly unless they ask for the poll.
      overrides: [
        appServicesProvider.overrideWithValue(demo),
        clockProvider.overrideWithValue(TestClock(testNow)),
        dataPollIntervalProvider.overrideWithValue(pollInterval),
        ...overrides,
      ],
      retry: (_, _) => null,
      child: wrap == null
          ? MemoraApp(initialLocation: initialLocation)
          : wrap(MemoraApp(initialLocation: initialLocation)),
    ),
  );
  await tester.pumpAndSettle();
  return demo;
}

/// Scrolls [finder] into the clear part of the viewport, past the header
/// and anything floating over the bottom, so it can be tapped.
Future<void> scrollTo(
  WidgetTester tester,
  Finder finder, {
  double bottomClearance = 130,
}) async {
  final scrollable = find.byType(Scrollable).last;
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  Rect? previous;
  for (var i = 0; i < 40; i++) {
    if (finder.evaluate().isNotEmpty) {
      final rect = tester.getRect(finder.first);
      final clear = rect.top > 70 && rect.bottom < height - bottomClearance;
      // Stop once it sits clear, or once the list will not move further.
      if (clear || (previous != null && (previous.top - rect.top).abs() < 1)) {
        return;
      }
      previous = rect;
    }
    await tester.drag(scrollable, const Offset(0, -150));
    await tester.pumpAndSettle();
  }
  throw StateError('Could not scroll $finder into view');
}
