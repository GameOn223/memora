import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

void main() {
  group('QueuePolicy window', () {
    const policy = QueuePolicy();

    test('defaults to overnight from 01:00 to 07:00', () {
      expect(policy.mode, QueueMode.overnight);
      expect(policy.isInsideWindow(DateTime(2026, 9, 15, 0, 59)), isFalse);
      expect(policy.isInsideWindow(DateTime(2026, 9, 15, 1, 0)), isTrue);
      expect(policy.isInsideWindow(DateTime(2026, 9, 15, 6, 59)), isTrue);
      expect(policy.isInsideWindow(DateTime(2026, 9, 15, 7, 0)), isFalse);
    });

    test('handles windows that cross midnight', () {
      const late = QueuePolicy(
        windowStartMinutes: 23 * 60,
        windowEndMinutes: 5 * 60,
      );
      expect(late.isInsideWindow(DateTime(2026, 9, 15, 23, 30)), isTrue);
      expect(late.isInsideWindow(DateTime(2026, 9, 16, 4, 59)), isTrue);
      expect(late.isInsideWindow(DateTime(2026, 9, 16, 12)), isFalse);
    });

    test('next window start is later today or tomorrow', () {
      expect(
        policy.nextWindowStart(DateTime(2026, 9, 15, 0, 30)),
        DateTime(2026, 9, 15, 1),
      );
      expect(
        policy.nextWindowStart(DateTime(2026, 9, 15, 9, 42)),
        DateTime(2026, 9, 16, 1),
      );
      final inside = DateTime(2026, 9, 15, 3);
      expect(policy.nextWindowStart(inside), inside);
    });

    test('pause wins over everything', () {
      final paused = policy.copyWith(paused: true);
      final night = DateTime(2026, 9, 15, 2);
      expect(paused.allowsProcessingAt(night), isFalse);
      expect(paused.allowsProcessingAt(night, processNow: true), isFalse);
    });

    test('immediate mode and process now ignore the window', () {
      final noon = DateTime(2026, 9, 15, 12);
      expect(policy.allowsProcessingAt(noon), isFalse);
      expect(policy.allowsProcessingAt(noon, processNow: true), isTrue);
      expect(
        policy.copyWith(mode: QueueMode.immediate).allowsProcessingAt(noon),
        isTrue,
      );
    });

    test('round-trips through JSON', () {
      const custom = QueuePolicy(
        mode: QueueMode.immediate,
        paused: true,
        windowStartMinutes: 30,
        windowEndMinutes: 300,
      );
      expect(QueuePolicy.fromJson(custom.toJson()), custom);
    });
  });
}
