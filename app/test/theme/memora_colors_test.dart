import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/theme/memora_colors.dart';
import 'package:memora/src/theme/memora_theme.dart';

void main() {
  group('MemoraColors', () {
    test('dark maps the design tokens', () {
      const c = MemoraColors.dark;
      expect(c.bg, const Color(0xFF161826));
      expect(c.surface, const Color(0xFF232532));
      expect(c.surface2, const Color(0xFF1C1E2B));
      expect(c.line, const Color(0xFF3F424D));
      expect(c.lineSoft, const Color(0xFF292B31));
      expect(c.muted, const Color(0xFF9397AB));
      expect(c.accentInk, const Color(0xFFD2CEFD));
      expect(c.accentTint, const Color(0xFF2B2741));
      expect(c.accentLine, const Color(0xFF5D5294));
      expect(c.stripeB, const Color(0xFF22242D));
    });

    test('light maps the design tokens', () {
      const c = MemoraColors.light;
      expect(c.bg, const Color(0xFFE4E7F5));
      expect(c.surface, const Color(0xFFF3F5FE));
      expect(c.text, const Color(0xFF292B31));
      expect(c.muted, const Color(0xFF595D6C));
      expect(c.accent, const Color(0xFF796CBF));
      expect(c.accentInk, const Color(0xFF5D5294));
      expect(c.accentTint, const Color(0xFFE7E5FE));
      expect(c.accentLine, const Color(0xFFB5ABFC));
      expect(c.lineSoft, const Color(0xFFDEE1EF));
      expect(c.scrim, const Color.fromRGBO(243, 245, 254, 0.93));
    });

    test('lerp blends every token', () {
      final mid = MemoraColors.dark.lerp(MemoraColors.light, 0.5);
      expect(
        mid.bg,
        Color.lerp(MemoraColors.dark.bg, MemoraColors.light.bg, 0.5),
      );
      expect(
        MemoraColors.dark.lerp(MemoraColors.light, 1).text,
        MemoraColors.light.text,
      );
    });

    test('themes carry the extension and Inter', () {
      expect(MemoraTheme.dark().extension<MemoraColors>(), MemoraColors.dark);
      expect(MemoraTheme.light().extension<MemoraColors>(), MemoraColors.light);
      expect(MemoraTheme.dark().scaffoldBackgroundColor, MemoraColors.dark.bg);
      expect(MemoraTheme.light().textTheme.bodyLarge!.fontFamily, 'Inter');
    });
  });
}
