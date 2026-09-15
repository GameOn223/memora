import 'package:flutter/material.dart';

import '../theme/memora_colors.dart';
import '../theme/tokens.dart';

/// The bottom sheet surface from the design: a grab handle, a top hairline,
/// large top corners and the medium shadow.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.lg),
        ),
        boxShadow: Shadows.md,
      ),
      padding: EdgeInsets.fromLTRB(
        Space.s4,
        Space.s3,
        Space.s4,
        Space.s6 + bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 3,
              margin: const EdgeInsets.only(bottom: Space.s3),
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// Opens [builder] in a Memora bottom sheet.
Future<T?> showMemoraSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
    ),
    builder: (context) => SheetScaffold(child: builder(context)),
  );
}
