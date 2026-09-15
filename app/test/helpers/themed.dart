import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:memora/src/theme/memora_theme.dart';

/// Wraps a single widget in the Memora theme for widget-level tests.
Widget themed(
  Widget child, {
  Brightness brightness = Brightness.dark,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    retry: (_, _) => null,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.dark
          ? MemoraTheme.dark()
          : MemoraTheme.light(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}
