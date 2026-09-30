@Tags(['screenshots'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/demo/demo_app_services.dart';
import 'package:memora/src/demo/demo_images.dart';
import 'package:memora/src/routing/router.dart';
import 'package:memora/src/services/app_services.dart';
import 'package:memora/src/state/ui_state.dart';
import 'package:memora/src/widgets/memory_image.dart';

import '../helpers/pump_app.dart';

/// Writes the README screenshots at 1080 x 2340, the size of a common
/// Android phone, with demo data and real rendered thumbnails.
///
/// Run with: flutter test --run-skipped -t screenshots
final outputDirectory = Directory('../docs/screenshots');

const _boundaryKey = ValueKey('screenshot-boundary');
const _pixelRatio = 2.625;

void main() {
  setUpAll(() {
    if (!outputDirectory.existsSync()) {
      outputDirectory.createSync(recursive: true);
    }
    PaintingBinding.instance.imageCache
      ..maximumSize = 500
      ..maximumSizeBytes = 512 << 20;
  });

  Future<DemoAppServices> open(
    WidgetTester tester,
    String location, {
    DemoAppServices? services,
    Brightness brightness = Brightness.dark,
  }) async {
    final demo = services ?? demoServices();
    // Paint and decode every demo image before the tree is built, so the
    // widgets resolve them straight from the image cache.
    await tester.runAsync(() => warmImages(demo));
    await pumpApp(
      tester,
      services: demo,
      initialLocation: location,
      platformBrightness: brightness,
      wrap: (app) => RepaintBoundary(key: _boundaryKey, child: app),
    );
    await tester.pumpAndSettle();
    return demo;
  }

  testWidgets('home', (tester) async {
    await open(tester, Routes.home);
    await shoot(tester, '01-home');
  });

  testWidgets('add', (tester) async {
    final services = await open(tester, Routes.add);
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
        .read(gallerySelectionProvider.notifier)
        .selectAll([
          for (final index in const [0, 1, 3, 4, 6, 9, 10])
            services.gallery.images[index].uri,
        ]);
    await tester.pumpAndSettle();
    await shoot(tester, '02-add');
  });

  testWidgets('queue', (tester) async {
    await open(tester, Routes.queue);
    await shoot(tester, '03-queue');
  });

  testWidgets('ask', (tester) async {
    await open(tester, Routes.ask);
    await scrollChat(tester, up: true);
    await shoot(tester, '04-ask');
  });

  testWidgets('ask with a table of sources', (tester) async {
    await open(tester, Routes.ask);
    await scrollChat(tester, up: false);
    await shoot(tester, '05-ask-table');
  });

  testWidgets('detail', (tester) async {
    await open(tester, '/memory/m9');
    await shoot(tester, '06-detail');
  });

  testWidgets('settings', (tester) async {
    await open(tester, Routes.settings);
    await shoot(tester, '07-settings');
  });

  testWidgets('onboarding', (tester) async {
    await open(
      tester,
      Routes.onboarding,
      services: demoServices(seed: false, onboardingComplete: false),
    );
    await shoot(tester, '08-onboarding');
  });

  testWidgets('browser', (tester) async {
    await open(tester, Routes.browser);
    await shoot(tester, '09-browser');
  });

  testWidgets('home at four columns', (tester) async {
    final services = demoServices();
    await services.preferences.setGridColumns(4);
    await open(tester, Routes.home, services: services);
    await shoot(tester, '10-home-dense');
  });

  testWidgets('home in the light theme', (tester) async {
    final services = demoServices();
    await services.preferences.setTheme(ThemePreference.light);
    await open(
      tester,
      Routes.home,
      services: services,
      brightness: Brightness.light,
    );
    await shoot(tester, '11-home-light');
  });

  testWidgets('empty', (tester) async {
    await open(tester, Routes.home, services: demoServices(seed: false));
    await shoot(tester, '12-empty');
  });
}

/// Renders every demo picture and decodes it into the image cache. Runs in
/// real async, since painting and decoding need the engine.
Future<void> warmImages(DemoAppServices services) async {
  for (final kind in DemoImageKind.values) {
    for (var seed = 0; seed < 8; seed++) {
      await services.renderer.render(kind, seed: seed);
    }
  }
  for (final path in services.db.images.keys.toList()) {
    await _resolve(MemoraFileImage(services.images, path));
  }
  for (final image in services.gallery.images) {
    await _resolve(DeviceThumbnailImage(services.gallery, image.uri));
  }
}

Future<void> _resolve(ImageProvider provider) {
  final completer = Completer<void>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void finish() {
    if (!completer.isCompleted) completer.complete();
    stream.removeListener(listener);
  }

  listener = ImageStreamListener(
    (image, _) => finish(),
    onError: (error, stack) => finish(),
  );
  stream.addListener(listener);
  return completer.future;
}

Future<void> scrollChat(WidgetTester tester, {required bool up}) async {
  final list = find.byType(ListView).first;
  for (var i = 0; i < 8; i++) {
    await tester.drag(list, Offset(0, up ? 600 : -600));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> shoot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('${outputDirectory.path}/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}
