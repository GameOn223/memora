import 'package:flutter/widgets.dart';

import '../theme/memora_colors.dart';
import '../theme/memora_icons.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import 'memora_icon_button.dart';

enum HeaderLeading { back, close, none }

/// Top bar of a screen: back or close, a title, and optional trailing items.
///
/// The design pads a 30px (or 32px on home) row by 16.8 above and 11.2
/// below. Here the row is 48px tall around the same center, with side
/// padding inside it, so icon buttons at the edges keep full touch targets
/// while everything lands on the same pixels.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.leading = HeaderLeading.back,
    this.onLeading,
    this.trailing = const [],
    this.brand = false,
  });

  final String title;
  final HeaderLeading leading;
  final VoidCallback? onLeading;
  final List<Widget> trailing;

  /// Larger brand title and 32px icons, as on the home screen.
  final bool brand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final safeTop = MediaQuery.paddingOf(context).top;
    final box = brand ? 32.0 : 30.0;
    final rowTop = Space.s6 + box / 2 - kMinTapTarget / 2;
    final bottom = box / 2 - 12.8;
    final gap = brand ? Space.s4 : Space.s3;

    return Padding(
      padding: EdgeInsets.only(top: safeTop + rowTop, bottom: bottom),
      child: SizedBox(
        height: kMinTapTarget,
        child: Row(
          children: [
            const SizedBox(width: Space.s6),
            if (leading != HeaderLeading.none) ...[
              Transform.translate(
                offset: const Offset(-7, 0),
                child: MemoraIconButton(
                  icon: leading == HeaderLeading.back
                      ? MemoraIcons.arrowLeft
                      : MemoraIcons.x,
                  semanticLabel: leading == HeaderLeading.back
                      ? 'Back'
                      : 'Close',
                  onPressed: onLeading,
                  box: 30,
                  iconSize: 18,
                  color: c.text,
                ),
              ),
              SizedBox(width: gap - 7),
            ],
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (brand ? MemoraText.brand : MemoraText.screenTitle)
                    .copyWith(color: c.text),
              ),
            ),
            for (final (i, item) in trailing.indexed) ...[
              SizedBox(width: gap),
              if (i == trailing.length - 1 && item is MemoraIconButton)
                Transform.translate(
                  offset: Offset(brand ? 6 : 7, 0),
                  child: item,
                )
              else
                item,
            ],
            const SizedBox(width: Space.s6),
          ],
        ),
      ),
    );
  }
}
