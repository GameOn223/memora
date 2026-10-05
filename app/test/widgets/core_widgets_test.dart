import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/theme/memora_icons.dart';
import 'package:memora/src/theme/tokens.dart';
import 'package:memora/src/widgets/fading_rule.dart';
import 'package:memora/src/widgets/memora_icon_button.dart';
import 'package:memora/src/widgets/memora_toggle.dart';
import 'package:memora/src/widgets/memory_tile.dart';
import 'package:memora/src/widgets/tags.dart';
import 'package:memora_core/memora_core.dart';

import '../helpers/themed.dart';

Memory _memory({
  ProcessingStatus status = ProcessingStatus.ready,
  DateTime? takenAt,
  DateTime? addedAt,
}) {
  final taken = takenAt ?? DateTime(2026, 9, 12, 21, 38);
  return Memory(
    id: 'm6',
    imagePath: 'originals/m6.png',
    source: MemorySource.gallery,
    sha256: 'abc',
    mimeType: 'image/png',
    width: 1080,
    height: 2400,
    byteSize: 412000,
    takenAt: taken,
    addedAt: addedAt ?? taken,
    updatedAt: taken,
    status: status,
    summary: 'Reliance electricity bill for August 2026',
    category: 'utility_bill',
  );
}

Widget _tile(Memory memory, int columns) => themed(
  SizedBox(
    width: 180,
    height: 240,
    child: MemoryTile(
      memory: memory,
      columns: columns,
      fact: '₹2,103 · paid',
      onTap: () {},
    ),
  ),
);

void main() {
  testWidgets('FadingRule paints a 1px gradient line', (tester) async {
    await tester.pumpWidget(
      themed(const SizedBox(width: 300, child: FadingRule())),
    );
    final paint = find.descendant(
      of: find.byType(FadingRule),
      matching: find.byType(CustomPaint),
    );
    expect(tester.getSize(paint), const Size(300, 1));
    expect(
      tester.renderObject(paint),
      paints..rect(rect: const Rect.fromLTWH(0, 0, 300, 1)),
    );
    final painter =
        tester.widget<CustomPaint>(paint).painter! as FadingRulePainter;
    expect(painter.fade, 48);
  });

  testWidgets('MemoraToggle toggles and exposes switch semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var value = false;
    await tester.pumpWidget(
      themed(
        StatefulBuilder(
          builder: (context, setState) => MemoraToggle(
            value: value,
            semanticLabel: 'Process overnight',
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(MemoraToggle)),
      matchesSemantics(
        label: 'Process overnight',
        hasToggledState: true,
        isToggled: false,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.byType(MemoraToggle));
    await tester.pumpAndSettle();
    expect(value, isTrue);
    expect(
      tester.getSemantics(find.byType(MemoraToggle)),
      matchesSemantics(
        label: 'Process overnight',
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('icon buttons get a 48px target around a 30px glyph box', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      themed(
        SizedBox(
          height: 48,
          width: 200,
          child: Center(
            child: MemoraIconButton(
              icon: MemoraIcons.arrowLeft,
              semanticLabel: 'Back',
              box: 30,
              onPressed: () => taps++,
            ),
          ),
        ),
      ),
    );
    final button = find.byType(MemoraIconButton);
    expect(tester.getSize(button), const Size(30, 30));
    // A tap 22px left of center is outside the glyph box but inside 48px.
    await tester.tapAt(tester.getCenter(button) - const Offset(22, 0));
    expect(taps, 1);
    final node = tester.getSemantics(button);
    expect(node.rect.size, const Size(48, 48));
    expect(node.label, 'Back');
    handle.dispose();
  });

  testWidgets('keyword chips are 26px pills that wrap onto more lines', (
    tester,
  ) async {
    const keywords = [
      'reliance',
      'electricity',
      'bill',
      'payment',
      'july',
      'due date',
    ];
    await tester.pumpWidget(
      themed(
        const SizedBox(
          width: 150,
          child: Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: [
              KeywordChip('reliance'),
              KeywordChip('electricity'),
              KeywordChip('bill'),
              KeywordChip('payment'),
              KeywordChip('july'),
              KeywordChip('due date'),
            ],
          ),
        ),
      ),
    );

    final chips = find.byType(KeywordChip);
    expect(chips, findsNWidgets(keywords.length));
    final rects = [
      for (final chip in chips.evaluate())
        tester.getRect(find.byWidget(chip.widget)),
    ];
    for (final (i, rect) in rects.indexed) {
      expect(rect.height, moreOrLessEquals(26), reason: keywords[i]);
      // 10px of padding either side of the label, inside the hairline.
      final label = tester.getRect(find.text(keywords[i]));
      expect(label.left - rect.left, moreOrLessEquals(11));
      expect(rect.right - label.right, moreOrLessEquals(11));
    }
    // Six chips cannot fit on one 150px line, so the wrap uses several and
    // every chip still lands inside it.
    expect({for (final rect in rects) rect.top}.length, greaterThan(1));
    final wrap = tester.getRect(find.byType(Wrap));
    for (final rect in rects) {
      expect(rect.left, greaterThanOrEqualTo(wrap.left));
      expect(rect.right, lessThanOrEqualTo(wrap.right));
    }
  });

  group('MemoryTile', () {
    testWidgets('shows title and meta at 2 columns', (tester) async {
      await tester.pumpWidget(_tile(_memory(), 2));
      expect(
        find.text('Reliance electricity bill for August 2026'),
        findsOneWidget,
      );
      expect(find.text('₹2,103 · PAID'), findsOneWidget);
      expect(find.byKey(MemoryTile.tileDotKey), findsNothing);
      expect(find.byKey(MemoryTile.addedLaterKey), findsNothing);
    });

    testWidgets('shows the status label instead of facts while queued', (
      tester,
    ) async {
      await tester.pumpWidget(
        _tile(_memory(status: ProcessingStatus.captured), 2),
      );
      expect(find.text('IN QUEUE'), findsOneWidget);
    });

    testWidgets('shows only a dot at 4 columns', (tester) async {
      await tester.pumpWidget(_tile(_memory(), 4));
      expect(find.byKey(MemoryTile.tileDotKey), findsOneWidget);
      expect(
        find.text('Reliance electricity bill for August 2026'),
        findsNothing,
      );
    });

    testWidgets('shows the image alone at 8 columns', (tester) async {
      await tester.pumpWidget(_tile(_memory(), 8));
      expect(find.byKey(MemoryTile.tileDotKey), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('marks memories added on a later day', (tester) async {
      final memory = _memory(
        takenAt: DateTime(2026, 8, 28, 20, 11),
        addedAt: DateTime(2026, 9, 15, 9, 12),
      );
      for (final columns in [2, 4, 8]) {
        await tester.pumpWidget(_tile(memory, columns));
        expect(find.byKey(MemoryTile.addedLaterKey), findsOneWidget);
      }
    });
  });
}
