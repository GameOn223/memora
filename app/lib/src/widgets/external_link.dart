import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/services.dart';
import '../theme/memora_colors.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import 'outline_action.dart';

/// A tappable address that opens outside Memora.
///
/// When nothing on the phone can open it, the address itself is shown so it
/// can be typed somewhere else. A link that silently does nothing is worse
/// than one that tells you where to go.
class ExternalLink extends ConsumerStatefulWidget {
  const ExternalLink({
    super.key,
    required this.label,
    required this.url,
    this.size = 12.5,
  });

  final String label;
  final String url;
  final double size;

  @override
  ConsumerState<ExternalLink> createState() => _ExternalLinkState();
}

class _ExternalLinkState extends ConsumerState<ExternalLink> {
  bool _failed = false;

  Future<void> _open() async {
    final handled = await ref.read(appServicesProvider).links.open(widget.url);
    if (!mounted) return;
    setState(() => _failed = !handled);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => unawaited(_open()),
          child: Text(
            widget.label,
            style: MemoraText.style(
              widget.size,
              height: 1.5,
              color: c.accent,
            ).copyWith(decoration: TextDecoration.underline),
            semanticsLabel: '${widget.label}, opens outside Memora',
          ),
        ),
        if (_failed) ...[
          const SizedBox(height: Space.s2),
          SelectableText(
            widget.url,
            style: MemoraText.style(11.5, height: 1.5, color: c.dim),
          ),
        ],
      ],
    );
  }
}

/// A link styled as an action, for the bottom of a dialog.
class ExternalLinkAction extends ConsumerWidget {
  const ExternalLinkAction({super.key, required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlineAction(
      label: label,
      tone: ActionTone.neutral,
      onPressed: () => unawaited(ref.read(appServicesProvider).links.open(url)),
    );
  }
}
