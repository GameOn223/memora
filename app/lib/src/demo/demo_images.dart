import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// The kinds of phone screenshots the demo paints.
enum DemoImageKind {
  bill,
  comparison,
  map,
  booking,
  receipt,
  code,
  chat,
  shopping,
}

/// Paints simple screenshot-like PNGs for demo memories and gallery images,
/// so tiles show pictures instead of stripes. Results are cached.
class DemoImageRenderer {
  DemoImageRenderer({this.width = 360, this.height = 720});

  final int width;
  final int height;
  final Map<String, Future<Uint8List>> _cache = {};

  Future<Uint8List> render(DemoImageKind kind, {int seed = 0}) {
    return _cache.putIfAbsent('${kind.name}-$seed', () => _paint(kind, seed));
  }

  Future<Uint8List> _paint(DemoImageKind kind, int seed) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(width.toDouble(), height.toDouble());
    final painter = _DemoPainter(canvas, size, math.Random(seed * 31 + 7));
    switch (kind) {
      case DemoImageKind.bill:
        painter.bill(seed);
      case DemoImageKind.comparison:
        painter.comparison(seed);
      case DemoImageKind.map:
        painter.map(seed);
      case DemoImageKind.booking:
        painter.booking(seed);
      case DemoImageKind.receipt:
        painter.receipt(seed);
      case DemoImageKind.code:
        painter.code(seed);
      case DemoImageKind.chat:
        painter.chat(seed);
      case DemoImageKind.shopping:
        painter.shopping(seed);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }
}

class _DemoPainter {
  _DemoPainter(this.canvas, this.size, this.random);

  final Canvas canvas;
  final Size size;
  final math.Random random;

  double get w => size.width;
  double get h => size.height;

  void fill(Color color) =>
      canvas.drawRect(Offset.zero & size, Paint()..color = color);

  void rect(
    double x,
    double y,
    double width,
    double height,
    Color color, {
    double radius = 0,
  }) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, width, height),
        Radius.circular(radius),
      ),
      Paint()..color = color,
    );
  }

  void text(
    String value,
    double x,
    double y, {
    double size = 14,
    Color color = const Color(0xFFFFFFFF),
    FontWeight weight = FontWeight.w500,
    double maxWidth = 300,
  }) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(fontFamily: 'Inter', fontSize: size),
          )
          ..pushStyle(
            ui.TextStyle(
              color: color,
              fontWeight: weight,
              fontVariations: [
                ui.FontVariation.weight(weight == FontWeight.w400 ? 400 : 600),
              ],
            ),
          )
          ..addText(value);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: maxWidth));
    canvas.drawParagraph(paragraph, Offset(x, y));
  }

  /// A run of rounded bars standing in for a line of small text.
  void textLine(
    double x,
    double y,
    double width,
    Color color, {
    double thickness = 7,
  }) {
    var cursor = x;
    while (cursor < x + width - 12) {
      final word = math.min(18 + random.nextDouble() * 46, x + width - cursor);
      rect(cursor, y, word, thickness, color, radius: thickness / 2);
      cursor += word + 6;
    }
  }

  void statusBar(Color color) {
    text('9:41', 18, 12, size: 12, color: color);
    rect(w - 64, 17, 16, 8, color, radius: 2);
    rect(w - 42, 17, 24, 8, color, radius: 2);
  }

  void bill(int seed) {
    const bg = Color(0xFF14213A);
    const card = Color(0xFF1D2D4D);
    const soft = Color(0xFF3A4E73);
    const ink = Color(0xFFE6ECF8);
    const blue = Color(0xFF4C8DFF);
    const amounts = [
      '₹1,842',
      '₹2,103',
      '₹1,690',
      '₹2,014',
      '₹2,088',
      '₹1,614',
      '₹1,402',
      '₹1,455',
    ];
    const months = [
      'September',
      'August',
      'July',
      'January',
      'February',
      'March',
      'May',
      'June',
    ];
    final i = seed % amounts.length;
    fill(bg);
    statusBar(ink);
    canvas.drawCircle(const Offset(38, 76), 16, Paint()..color = blue);
    text('Reliance Energy', 64, 62, size: 15, color: ink);
    text(
      'Consumer no. 4471',
      64,
      82,
      size: 10,
      color: soft,
      weight: FontWeight.w400,
    );
    rect(18, 118, w - 36, 190, card, radius: 16);
    text('Electricity bill · ${months[i]}', 36, 138, size: 12, color: soft);
    text(amounts[i], 36, 162, size: 40, color: ink);
    text(
      'Due in 12 days',
      36,
      218,
      size: 12,
      color: const Color(0xFF8FB4FF),
      weight: FontWeight.w400,
    );
    rect(36, 256, w - 72, 36, blue, radius: 10);
    text('Pay now', w / 2 - 26, 265, size: 13, color: const Color(0xFFFFFFFF));
    for (var r = 0; r < 5; r++) {
      final y = 336.0 + r * 46;
      rect(18, y, w - 36, 36, card, radius: 10);
      textLine(34, y + 14, w * 0.35, soft);
      rect(w - 94, y + 12, 58, 11, soft, radius: 5);
    }
    rect(18, h - 108, w - 36, 80, card, radius: 16);
    textLine(34, h - 86, w - 120, soft);
    textLine(34, h - 64, w - 170, soft);
  }

  void comparison(int seed) {
    const bg = Color(0xFFF1EEE7);
    const ink = Color(0xFF26231E);
    const soft = Color(0xFFCFC8BA);
    const accent = Color(0xFF2F6B55);
    fill(bg);
    statusBar(ink);
    text(
      seed.isEven ? 'Compare laptops' : 'Price tracker',
      18,
      54,
      size: 20,
      color: ink,
    );
    for (var c = 0; c < 2; c++) {
      final x = 18.0 + c * ((w - 46) / 2 + 10);
      final cw = (w - 46) / 2;
      rect(x, 98, cw, 110, const Color(0xFFE2DDD2), radius: 12);
      rect(x + cw / 2 - 34, 128, 68, 44, const Color(0xFFBDB5A6), radius: 4);
      text(
        c == 0 ? 'MacBook Air' : 'ThinkPad X1',
        x + 6,
        220,
        size: 12,
        color: ink,
      );
      text(
        c == 0 ? '₹1,24,900' : '₹1,12,400',
        x + 6,
        240,
        size: 15,
        color: accent,
      );
    }
    for (var r = 0; r < 9; r++) {
      final y = 286.0 + r * 40;
      if (r.isEven) {
        rect(12, y - 8, w - 24, 38, const Color(0xFFE7E2D8), radius: 6);
      }
      textLine(22, y + 4, w * 0.28, soft);
      rect(
        w * 0.45,
        y + 2,
        40 + random.nextDouble() * 40,
        10,
        const Color(0xFF9F9786),
        radius: 5,
      );
      rect(
        w * 0.75,
        y + 2,
        40 + random.nextDouble() * 30,
        10,
        const Color(0xFF9F9786),
        radius: 5,
      );
    }
  }

  void map(int seed) {
    const land = Color(0xFF1E2A26);
    const block = Color(0xFF26352F);
    const road = Color(0xFF3D4F48);
    const major = Color(0xFF5D6F66);
    const ink = Color(0xFFE3ECE7);
    fill(land);
    for (var i = 0; i < 18; i++) {
      rect(
        random.nextDouble() * w,
        random.nextDouble() * h * 0.7,
        40 + random.nextDouble() * 70,
        30 + random.nextDouble() * 60,
        block,
        radius: 4,
      );
    }
    final water = Path()
      ..moveTo(0, h * 0.18)
      ..cubicTo(w * 0.3, h * 0.26, w * 0.5, h * 0.08, w, h * 0.2)
      ..lineTo(w, h * 0.25)
      ..cubicTo(w * 0.5, h * 0.14, w * 0.3, h * 0.32, 0, h * 0.24)
      ..close();
    canvas.drawPath(water, Paint()..color = const Color(0xFF1C3342));
    final roads = Paint()
      ..color = road
      ..strokeWidth = 6;
    for (var i = 0; i < 7; i++) {
      final y = 60.0 + i * 70;
      canvas.drawLine(Offset(0, y), Offset(w, y + 30), roads);
    }
    final main = Paint()
      ..color = major
      ..strokeWidth = 12;
    canvas
      ..drawLine(Offset(w * 0.3, 0), Offset(w * 0.55, h * 0.72), main)
      ..drawLine(Offset(0, h * 0.5), Offset(w, h * 0.42), main);
    final pin = Offset(w * (0.45 + seed % 3 * 0.06), h * 0.38);
    canvas
      ..drawCircle(pin, 20, Paint()..color = const Color(0x55E86A5A))
      ..drawCircle(pin, 9, Paint()..color = const Color(0xFFE86A5A));
    rect(0, h * 0.72, w, h * 0.28, const Color(0xFF151D1A));
    rect(w / 2 - 22, h * 0.72 + 10, 44, 4, road, radius: 2);
    text(
      seed.isEven ? 'Coffee roastery' : 'East gate parking',
      20,
      h * 0.72 + 30,
      size: 18,
      color: ink,
    );
    text(
      seed.isEven ? 'Open · Closes 22:00' : 'Level 2 · gate B',
      20,
      h * 0.72 + 58,
      size: 12,
      color: const Color(0xFF8FC5A8),
      weight: FontWeight.w400,
    );
    textLine(20, h * 0.72 + 92, w - 60, road);
    rect(20, h - 62, 120, 36, const Color(0xFF2F6F55), radius: 18);
    text('Directions', 42, h - 52, size: 13, color: ink);
  }

  void booking(int seed) {
    const bg = Color(0xFF1B1F38);
    const card = Color(0xFFF4F2FA);
    const ink = Color(0xFF1B1F38);
    const soft = Color(0xFFC9C5DA);
    fill(bg);
    statusBar(const Color(0xFFE8E6F4));
    text('Your trip', 20, 56, size: 22, color: const Color(0xFFFFFFFF));
    rect(18, 104, w - 36, 330, card, radius: 18);
    text('BLR', 40, 136, size: 34, color: ink);
    text('GOA', w - 118, 136, size: 34, color: ink);
    text(
      '06:35',
      42,
      182,
      size: 13,
      color: const Color(0xFF5B5874),
      weight: FontWeight.w400,
    );
    text(
      '07:50',
      w - 116,
      182,
      size: 13,
      color: const Color(0xFF5B5874),
      weight: FontWeight.w400,
    );
    final dash = Paint()
      ..color = soft
      ..strokeWidth = 2;
    for (var x = 40.0; x < w - 40; x += 12) {
      canvas.drawLine(Offset(x, 232), Offset(x + 6, 232), dash);
    }
    text('6E 2134 · 18 Oct · Seat 14C', 40, 252, size: 13, color: ink);
    text('PNR K4T9RB', 40, 276, size: 13, color: const Color(0xFF4A45A0));
    for (var i = 0; i < 38; i++) {
      final bw = 2.0 + random.nextInt(4);
      rect(40 + i * 7.0, 330, bw, 70, ink);
    }
    rect(18, 458, w - 36, 64, const Color(0xFF262B4D), radius: 14);
    textLine(36, 482, w - 100, const Color(0xFF3B416B));
    rect(18, 536, w - 36, 64, const Color(0xFF262B4D), radius: 14);
    textLine(36, 560, w - 140, const Color(0xFF3B416B));
  }

  void receipt(int seed) {
    const bg = Color(0xFF2A2C33);
    const paper = Color(0xFFEDE9E0);
    const ink = Color(0xFF3B3833);
    const soft = Color(0xFFBDB7AB);
    fill(bg);
    rect(26, 28, w - 52, h - 70, paper, radius: 4);
    text('FRESH MART', w / 2 - 52, 58, size: 18, color: ink);
    textLine(w / 2 - 70, 88, 140, soft, thickness: 6);
    for (var r = 0; r < 14; r++) {
      final y = 130.0 + r * 28;
      textLine(46, y, w * 0.45, soft, thickness: 6);
      rect(w - 110, y, 50, 6, const Color(0xFF9C968A), radius: 3);
    }
    final line = Paint()
      ..color = ink
      ..strokeWidth = 1;
    canvas.drawLine(Offset(46, h - 190), Offset(w - 46, h - 190), line);
    text('TOTAL', 46, h - 176, size: 15, color: ink);
    text(
      seed.isEven ? '₹3,218' : '₹1,12,400',
      w - 132,
      h - 176,
      size: 15,
      color: ink,
    );
    textLine(46, h - 130, w - 120, soft, thickness: 6);
    for (var i = 0; i < 30; i++) {
      rect(60 + i * 8.0, h - 100, 2.0 + random.nextInt(3), 34, ink);
    }
  }

  void code(int seed) {
    const bg = Color(0xFF17191F);
    const gutter = Color(0xFF3A3E4A);
    const palette = [
      Color(0xFFB392F0),
      Color(0xFF7BC99A),
      Color(0xFFE6A26B),
      Color(0xFF8AB4F8),
      Color(0xFF6B7080),
    ];
    fill(bg);
    statusBar(const Color(0xFFD7DAE3));
    text('MainActivity.kt', 18, 50, size: 14, color: const Color(0xFFD7DAE3));
    rect(0, 80, w, 1, const Color(0xFF262A33));
    for (var r = 0; r < 26; r++) {
      final y = 98.0 + r * 22;
      text(
        '${r + 1}',
        14,
        y - 3,
        size: 10,
        color: gutter,
        weight: FontWeight.w400,
      );
      var x = 44.0 + (r % 5 == 0 ? 0 : 16.0 * (1 + random.nextInt(2)));
      final tokens = 2 + random.nextInt(4);
      for (var t = 0; t < tokens && x < w - 20; t++) {
        final tw = 16 + random.nextDouble() * 60;
        rect(x, y, tw, 8, palette[random.nextInt(palette.length)], radius: 3);
        x += tw + 8;
      }
    }
  }

  void chat(int seed) {
    const bg = Color(0xFF0F1B20);
    const theirs = Color(0xFF223238);
    const mine = Color(0xFF1E5A4A);
    const ink = Color(0xFFDDE8E4);
    fill(bg);
    statusBar(ink);
    rect(0, 38, w, 58, const Color(0xFF16252B));
    canvas.drawCircle(
      const Offset(40, 67),
      16,
      Paint()..color = const Color(0xFF4E7D6E),
    );
    text('Vendor · Quotes', 66, 58, size: 15, color: ink);
    var y = 118.0;
    for (var i = 0; i < 8; i++) {
      final right = (i + seed).isOdd;
      final bw = 130 + random.nextDouble() * 110;
      final bh = 36 + random.nextInt(3) * 16.0;
      final x = right ? w - bw - 14 : 14.0;
      rect(x, y, bw, bh, right ? mine : theirs, radius: 14);
      textLine(
        x + 12,
        y + 14,
        bw - 24,
        right ? const Color(0xFF3F7D6B) : const Color(0xFF3A4D54),
      );
      if (i == 3) {
        text('₹48,000', x + 12, y + bh - 22, size: 13, color: ink);
      }
      y += bh + 14;
    }
    rect(10, h - 58, w - 20, 44, const Color(0xFF1A2A30), radius: 22);
  }

  void shopping(int seed) {
    const bg = Color(0xFFF6F6F8);
    const ink = Color(0xFF1F2330);
    const soft = Color(0xFFD9DBE3);
    fill(bg);
    statusBar(ink);
    rect(14, 46, w - 28, 38, const Color(0xFFE9EAF0), radius: 19);
    rect(14, 100, w - 28, 250, const Color(0xFFE3E5EC), radius: 14);
    rect(w / 2 - 90, 150, 180, 110, const Color(0xFF2E3445), radius: 8);
    rect(w / 2 - 110, 262, 220, 12, const Color(0xFF9DA3B4), radius: 6);
    text(
      seed.isEven ? 'UltraSharp 27 monitor' : 'MacBook Air M4',
      18,
      368,
      size: 17,
      color: ink,
    );
    text(
      seed.isEven ? '₹24,499' : '₹1,24,900',
      18,
      398,
      size: 24,
      color: const Color(0xFFB4323C),
    );
    text(
      seed.isEven ? 'was ₹31,000' : '3 variants',
      140,
      406,
      size: 12,
      color: const Color(0xFF7A7F8F),
      weight: FontWeight.w400,
    );
    for (var s = 0; s < 5; s++) {
      canvas.drawCircle(
        Offset(26.0 + s * 18, 448),
        6,
        Paint()..color = const Color(0xFFE9A23B),
      );
    }
    textLine(18, 476, w - 60, soft);
    textLine(18, 496, w - 110, soft);
    rect(18, h - 86, w - 36, 48, const Color(0xFFF3C33B), radius: 24);
    text('Add to cart', w / 2 - 38, h - 71, size: 14, color: ink);
  }
}
