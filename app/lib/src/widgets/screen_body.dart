import 'package:flutter/widgets.dart';

import '../theme/memora_colors.dart';

/// Standard screen layout: a header, then content that fills the rest.
///
/// Screens sit inside the app shell, which already paints the background
/// and handles the bottom bar, so this only deals with the top inset.
class ScreenBody extends StatelessWidget {
  const ScreenBody({
    super.key,
    required this.header,
    required this.child,
    this.footer,
  });

  final Widget header;
  final Widget child;

  /// Pinned to the bottom, above the system inset.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(child: child),
          ?footer,
        ],
      ),
    );
  }
}
