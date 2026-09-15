import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'memora_colors.dart';
import 'text_styles.dart';
import 'tokens.dart';

/// Material theme carrying the Nocturne tokens. Most Memora widgets draw
/// themselves from [MemoraColors]; this keeps the few Material pieces in use
/// (dialogs, menus, text fields, sheets) on the same palette.
abstract final class MemoraTheme {
  static ThemeData dark() => _build(Brightness.dark, MemoraColors.dark);

  static ThemeData light() => _build(Brightness.light, MemoraColors.light);

  static ThemeData _build(Brightness brightness, MemoraColors c) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.bg,
      secondary: c.accentInk,
      onSecondary: c.bg,
      error: c.accentInk,
      onError: c.bg,
      surface: c.surface,
      onSurface: c.text,
      surfaceContainerLowest: c.bg,
      surfaceContainerLow: c.surface2,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surface,
      surfaceContainerHighest: c.surface,
      onSurfaceVariant: c.muted,
      outline: c.line,
      outlineVariant: c.lineSoft,
      primaryContainer: c.accentTint,
      onPrimaryContainer: c.accentInk,
      shadow: Colors.black,
      scrim: c.scrim,
    );
    final base = MemoraText.body.copyWith(color: c.text);
    TextStyle sized(double size, {bool medium = false}) =>
        MemoraText.style(size, medium: medium, color: c.text);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.md),
      side: BorderSide(color: c.line),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: MemoraText.family,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      dividerColor: c.lineSoft,
      splashFactory: InkRipple.splashFactory,
      splashColor: c.accent.withValues(alpha: 0.08),
      highlightColor: c.text.withValues(alpha: 0.04),
      hoverColor: c.text.withValues(alpha: 0.04),
      focusColor: c.accent.withValues(alpha: 0.12),
      extensions: [c],
      textTheme: TextTheme(
        displayLarge: sized(29, medium: true),
        headlineMedium: sized(24, medium: true),
        titleLarge: sized(20, medium: true),
        titleMedium: sized(17, medium: true),
        titleSmall: sized(14, medium: true),
        bodyLarge: base,
        bodyMedium: sized(13.5),
        bodySmall: sized(12),
        labelLarge: sized(14, medium: true),
        labelMedium: sized(12, medium: true),
        labelSmall: sized(10, medium: true),
      ),
      iconTheme: IconThemeData(color: c.muted, size: 19),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accent.withValues(alpha: 0.32),
        selectionHandleColor: c.accent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: c.line),
        ),
        titleTextStyle: sized(17, medium: true),
        contentTextStyle: MemoraText.style(13.5, height: 1.55, color: c.muted),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: shape,
        textStyle: MemoraText.style(14, color: c.text),
        elevation: 6,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Colors.black.withValues(alpha: 0.5),
        elevation: 0,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accentInk,
          textStyle: MemoraText.style(14, medium: true),
          minimumSize: const Size(kMinTapTarget, kMinTapTarget),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: c.surface2,
        hintStyle: MemoraText.style(13.5, color: c.dim),
        labelStyle: MemoraText.style(13.5, color: c.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: c.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: c.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: c.accentLine),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surface,
        contentTextStyle: MemoraText.style(13.5, color: c.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: BorderSide(color: c.accentLine),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.lineSoft,
      ),
    );
  }

  /// Status and navigation bar styling for edge-to-edge drawing.
  static SystemUiOverlayStyle overlayStyle(Brightness brightness) {
    final darkIcons = brightness == Brightness.light;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      statusBarIconBrightness: darkIcons ? Brightness.dark : Brightness.light,
      statusBarBrightness: brightness,
      systemNavigationBarIconBrightness: darkIcons
          ? Brightness.dark
          : Brightness.light,
    );
  }
}
