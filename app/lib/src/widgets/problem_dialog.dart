import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/services.dart';

/// A page worth opening to settle a problem, shown as a button on the
/// dialog.
@immutable
class ProblemLink {
  const ProblemLink({required this.label, required this.url});

  final String label;
  final String url;
}

/// Shows something that went wrong, with the page that settles it.
///
/// A refusal used to be a line of small print under the section, where it
/// was easy to miss after tapping a button and watching nothing happen.
/// Something that stops the thing you asked for deserves to interrupt.
Future<void> showProblem(
  BuildContext context, {
  required String title,
  required String message,
  ProblemLink? link,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      if (link != null)
        Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () {
              unawaited(ref.read(appServicesProvider).links.open(link.url));
              Navigator.of(context).pop();
            },
            child: Text(link.label),
          ),
        ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  ),
);
