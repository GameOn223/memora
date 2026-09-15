import 'package:flutter/material.dart';

import 'tokens.dart';

/// Every `--m-*` token from the design, for dark and light themes.
///
/// Widgets never hard-code a color. They read `context.colors`.
@immutable
class MemoraColors extends ThemeExtension<MemoraColors> {
  const MemoraColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.lineSoft,
    required this.text,
    required this.muted,
    required this.dim,
    required this.accent,
    required this.accentInk,
    required this.accentTint,
    required this.accentLine,
    required this.stripeA,
    required this.stripeB,
    required this.scrim,
    required this.chip,
  });

  static const dark = MemoraColors(
    bg: Nocturne.bg,
    surface: Nocturne.surface,
    surface2: Color(0xFF1C1E2B),
    line: Nocturne.neutral800,
    lineSoft: Nocturne.neutral900,
    text: Nocturne.text,
    muted: Nocturne.neutral500,
    dim: Nocturne.neutral600,
    accent: Nocturne.accent,
    accentInk: Nocturne.accent300,
    accentTint: Nocturne.accent900,
    accentLine: Nocturne.accent700,
    stripeA: Nocturne.neutral900,
    stripeB: Color(0xFF22242D),
    scrim: Color.fromRGBO(18, 20, 32, 0.92),
    chip: Color(0xFF1C1E2B),
  );

  static const light = MemoraColors(
    bg: Nocturne.neutral200,
    surface: Nocturne.neutral100,
    surface2: Color(0xFFECEFFB),
    line: Nocturne.neutral300,
    lineSoft: Color(0xFFDEE1EF),
    text: Nocturne.neutral900,
    muted: Nocturne.neutral700,
    dim: Nocturne.neutral600,
    accent: Nocturne.accent600,
    accentInk: Nocturne.accent700,
    accentTint: Nocturne.accent200,
    accentLine: Nocturne.accent400,
    stripeA: Color(0xFFDEE1EF),
    stripeB: Color(0xFFE8EBF7),
    scrim: Color.fromRGBO(243, 245, 254, 0.93),
    chip: Color(0xFFECEFFB),
  );

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color line;
  final Color lineSoft;
  final Color text;
  final Color muted;
  final Color dim;
  final Color accent;
  final Color accentInk;
  final Color accentTint;
  final Color accentLine;
  final Color stripeA;
  final Color stripeB;
  final Color scrim;
  final Color chip;

  /// Accent veil laid over a selected gallery image, bottom to top. The
  /// design uses the dark accent in both themes.
  static const selectionVeil = [Color(0x479184D9), Color(0x1A9184D9)];

  @override
  MemoraColors copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? line,
    Color? lineSoft,
    Color? text,
    Color? muted,
    Color? dim,
    Color? accent,
    Color? accentInk,
    Color? accentTint,
    Color? accentLine,
    Color? stripeA,
    Color? stripeB,
    Color? scrim,
    Color? chip,
  }) {
    return MemoraColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      line: line ?? this.line,
      lineSoft: lineSoft ?? this.lineSoft,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      dim: dim ?? this.dim,
      accent: accent ?? this.accent,
      accentInk: accentInk ?? this.accentInk,
      accentTint: accentTint ?? this.accentTint,
      accentLine: accentLine ?? this.accentLine,
      stripeA: stripeA ?? this.stripeA,
      stripeB: stripeB ?? this.stripeB,
      scrim: scrim ?? this.scrim,
      chip: chip ?? this.chip,
    );
  }

  @override
  MemoraColors lerp(ThemeExtension<MemoraColors>? other, double t) {
    if (other is! MemoraColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return MemoraColors(
      bg: mix(bg, other.bg),
      surface: mix(surface, other.surface),
      surface2: mix(surface2, other.surface2),
      line: mix(line, other.line),
      lineSoft: mix(lineSoft, other.lineSoft),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      dim: mix(dim, other.dim),
      accent: mix(accent, other.accent),
      accentInk: mix(accentInk, other.accentInk),
      accentTint: mix(accentTint, other.accentTint),
      accentLine: mix(accentLine, other.accentLine),
      stripeA: mix(stripeA, other.stripeA),
      stripeB: mix(stripeB, other.stripeB),
      scrim: mix(scrim, other.scrim),
      chip: mix(chip, other.chip),
    );
  }
}

extension MemoraColorsContext on BuildContext {
  MemoraColors get colors =>
      Theme.of(this).extension<MemoraColors>() ?? MemoraColors.dark;
}
