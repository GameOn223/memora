import 'package:flutter/material.dart';
import 'package:memora_core/memora_core.dart';

import '../../theme/memora_colors.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';

/// What leaves the phone when a cloud provider is switched on. Shown once
/// per provider, before the first capability is pointed at it.
Future<bool> showCloudDisclosure(
  BuildContext context,
  ProviderDescriptor provider,
) async {
  final c = context.colors;
  const items = [
    'The image being processed',
    'The text and facts Memora extracted from it',
    'Your questions and the prompts Memora builds',
    'Recent messages in the conversation',
  ];
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Send data to ${provider.displayName}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'While ${provider.displayName} handles a capability, these leave '
            'your device for each request:',
            style: MemoraText.style(13.5, height: 1.55, color: c.muted),
          ),
          const SizedBox(height: Space.s3),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('·', style: MemoraText.style(13.5, color: c.accent)),
                  const SizedBox(width: Space.s2),
                  Expanded(
                    child: Text(
                      item,
                      style: MemoraText.style(13.5, height: 1.5, color: c.text),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Space.s3),
          Text(
            "${provider.displayName}'s own terms apply to those requests. "
            'Memora keeps nothing off your phone.',
            style: MemoraText.style(12.5, height: 1.55, color: c.muted),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  return accepted ?? false;
}
