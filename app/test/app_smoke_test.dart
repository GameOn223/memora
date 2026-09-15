import 'package:flutter_test/flutter_test.dart';
import 'package:memora/main.dart';

void main() {
  testWidgets('app starts', (tester) async {
    await tester.pumpWidget(const MemoraApp());
    expect(find.text('Memora'), findsOneWidget);
  });
}
