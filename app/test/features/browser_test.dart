import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/features/detail/detail_screen.dart';
import 'package:memora/src/routing/router.dart';
import 'package:memora/src/widgets/memory_image.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('shows sort, facets and every memory', (tester) async {
    await pumpApp(tester, initialLocation: Routes.browser);

    expect(find.text('All memories'), findsOneWidget);
    expect(find.text('SORT'), findsOneWidget);
    for (final sort in ['Newest', 'Oldest', 'Category']) {
      expect(find.text(sort), findsOneWidget);
    }
    expect(find.text('CATEGORY'), findsOneWidget);
    expect(find.text('IMAGE TAKEN'), findsOneWidget);
    expect(find.text('PROCESSING'), findsOneWidget);
    expect(find.text('17 of 17'), findsOneWidget);
  });

  testWidgets('a category facet narrows the results', (tester) async {
    await pumpApp(tester, initialLocation: Routes.browser);

    await tester.tap(find.text('Bills'));
    await tester.pumpAndSettle();
    expect(find.text('9 of 17'), findsOneWidget);

    // Tapping again clears the facet.
    await tester.tap(find.text('Bills'));
    await tester.pumpAndSettle();
    expect(find.text('17 of 17'), findsOneWidget);
  });

  testWidgets('the processing facet filters by status', (tester) async {
    await pumpApp(tester, initialLocation: Routes.browser);

    await tester.tap(find.text('Failed'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 17'), findsOneWidget);
  });

  testWidgets('a result opens the memory', (tester) async {
    await pumpApp(tester, initialLocation: Routes.browser);

    await tester.tap(find.byType(MemoryImageView).first);
    await tester.pumpAndSettle();
    expect(find.byType(DetailScreen), findsOneWidget);
  });
}
