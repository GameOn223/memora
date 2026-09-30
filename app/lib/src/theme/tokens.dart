import 'package:flutter/painting.dart';

/// Raw Nocturne design system values. Widgets read colors through
/// `MemoraColors` instead of these ramps, so both themes stay in sync.
abstract final class Nocturne {
  static const bg = Color(0xFF161826);
  static const surface = Color(0xFF232532);
  static const text = Color(0xFFE9E9ED);
  static const accent = Color(0xFF9184D9);

  static const neutral100 = Color(0xFFF3F5FE);
  static const neutral200 = Color(0xFFE4E7F5);
  static const neutral300 = Color(0xFFCFD3E5);
  static const neutral400 = Color(0xFFB2B6CA);
  static const neutral500 = Color(0xFF9397AB);
  static const neutral600 = Color(0xFF75798C);
  static const neutral700 = Color(0xFF595D6C);
  static const neutral800 = Color(0xFF3F424D);
  static const neutral900 = Color(0xFF292B31);

  static const accent100 = Color(0xFFF5F4FF);
  static const accent200 = Color(0xFFE7E5FE);
  static const accent300 = Color(0xFFD2CEFD);
  static const accent400 = Color(0xFFB5ABFC);
  static const accent500 = Color(0xFF968AE0);
  static const accent600 = Color(0xFF796CBF);
  static const accent700 = Color(0xFF5D5294);
  static const accent800 = Color(0xFF423A6A);
  static const accent900 = Color(0xFF2B2741);
}

/// Spacing scale, `--space-1` to `--space-8`.
abstract final class Space {
  static const double s1 = 2.8;
  static const double s2 = 5.6;
  static const double s3 = 8.4;
  static const double s4 = 11.2;
  static const double s6 = 16.8;
  static const double s8 = 22.4;
}

/// Corner radii, `--radius-sm`, `--radius-md` and `--radius-lg`.
abstract final class Radii {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 14;
}

/// Elevation used by toasts and sheets: a hairline ring plus a soft drop.
abstract final class Shadows {
  static const md = [
    BoxShadow(color: Nocturne.neutral700, spreadRadius: 1),
    BoxShadow(color: Color(0x8C000000), offset: Offset(0, 6), blurRadius: 18),
  ];
}

/// Minimum size of anything tappable, in logical pixels.
const double kMinTapTarget = 48;
