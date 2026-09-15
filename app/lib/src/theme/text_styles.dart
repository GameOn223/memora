import 'package:flutter/painting.dart';

/// Type used across Memora. Inter everywhere, weight 500 at most.
///
/// Inter ships as a variable font, so weight and optical size are passed as
/// font variations as well as a [FontWeight]. Browsers pick the optical size
/// from the font size automatically; this does the same.
abstract final class MemoraText {
  static const family = 'Inter';

  static TextStyle style(
    double size, {
    bool medium = false,
    double spacing = 0,
    double? height,
    bool tabular = false,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: medium ? FontWeight.w500 : FontWeight.w400,
      fontVariations: [
        FontVariation.weight(medium ? 500 : 400),
        FontVariation('opsz', size.clamp(14, 32).toDouble()),
      ],
      letterSpacing: spacing,
      height: height,
      leadingDistribution: TextLeadingDistribution.even,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
      color: color,
    );
  }

  /// Uppercase tracked metadata. Pair with `CapsLabel`, which uppercases.
  static TextStyle caps(
    double size, {
    double spacing = 1.1,
    double? height,
    bool tabular = false,
    Color? color,
  }) => style(
    size,
    medium: true,
    spacing: spacing,
    height: height,
    tabular: tabular,
    color: color,
  );

  /// "Memora" in the home header.
  static final brand = style(19, medium: true, spacing: -0.4);

  /// Titles in screen headers such as "Processing queue".
  static final screenTitle = style(17, medium: true, spacing: -0.2);

  static final body = style(14);
  static final bodyMedium = style(14, medium: true);
}
