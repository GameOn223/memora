import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads Inter and the Phosphor icon font before any test runs, so layouts
/// measure real glyphs instead of the square test font.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadMemoraFonts();
  await testMain();
}

Future<void> loadMemoraFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
  final phosphor = FontLoader('packages/phosphor_flutter/PhosphorRegular')
    ..addFont(
      rootBundle.load('packages/phosphor_flutter/lib/fonts/Phosphor.ttf'),
    );
  final phosphorFill = FontLoader('packages/phosphor_flutter/PhosphorFill')
    ..addFont(
      rootBundle.load('packages/phosphor_flutter/lib/fonts/Phosphor-Fill.ttf'),
    );
  await Future.wait([inter.load(), phosphor.load(), phosphorFill.load()]);
}
