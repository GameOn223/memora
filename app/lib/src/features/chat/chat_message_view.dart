import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:memora_core/memora_core.dart';

import '../../routing/router.dart';
import '../../theme/memora_colors.dart';
import '../../theme/memora_icons.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/caps_label.dart';
import '../../widgets/memory_image.dart';
import '../../widgets/memory_labels.dart';
import '../../widgets/tap_area.dart';

/// Indent that lines the answer's blocks up with its text, past the dot.
const double _answerIndent = 13.4;

/// One message in the conversation: a question bubble or an answer with its
/// headline, reasoning and sources.
class ChatMessageView extends StatefulWidget {
  const ChatMessageView({
    super.key,
    required this.message,
    required this.sources,
  });

  final ChatMessage message;

  /// Details for every memory the message cites, by id.
  final Map<String, MemoryDetails> sources;

  @override
  State<ChatMessageView> createState() => _ChatMessageViewState();
}

class _ChatMessageViewState extends State<ChatMessageView> {
  bool _planOpen = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final message = widget.message;
    if (message.role == MessageRole.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.85,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: c.accentTint,
              border: Border.all(color: c.accentLine),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(
              message.content,
              style: MemoraText.style(13.5, height: 1.45, color: c.text),
            ),
          ),
        ),
      );
    }

    final presentation = message.presentation ?? const MessagePresentation();
    final sources = [
      for (final reference in message.references)
        if (widget.sources[reference.memoryId] case final MemoryDetails d) d,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Text(
                message.content,
                style: MemoraText.style(13.5, height: 1.5, color: c.text),
              ),
            ),
          ],
        ),
        if (presentation.headline != null) ...[
          const SizedBox(height: Space.s4),
          Padding(
            padding: const EdgeInsets.only(left: _answerIndent),
            child: Container(
              padding: const EdgeInsets.only(left: Space.s4),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: c.accent, width: 2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    presentation.headline!,
                    style: MemoraText.style(
                      26,
                      medium: true,
                      spacing: -0.8,
                      height: 1.1,
                      tabular: true,
                      color: c.text,
                    ),
                  ),
                  if (headlineNote(presentation) case final String note) ...[
                    const SizedBox(height: Space.s2),
                    CapsLabel(note, size: 10, spacing: 1.1, color: c.muted),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (message.toolTrace.isNotEmpty) ...[
          const SizedBox(height: Space.s4),
          Padding(
            padding: const EdgeInsets.only(left: _answerIndent),
            child: TapArea(
              onTap: () => setState(() => _planOpen = !_planOpen),
              semanticLabel: 'How this was found',
              minSize: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s4,
                  vertical: Space.s3,
                ),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(color: c.lineSoft),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(MemoraIcons.gitBranch, size: 13, color: c.accent),
                        const SizedBox(width: 7),
                        Expanded(
                          child: CapsLabel(
                            'How this was found',
                            size: 9.5,
                            spacing: 1.1,
                            color: c.muted,
                          ),
                        ),
                        Transform.rotate(
                          angle: _planOpen ? 3.14159 : 0,
                          child: Icon(
                            MemoraIcons.caretDown,
                            size: 12,
                            color: c.dim,
                          ),
                        ),
                      ],
                    ),
                    if (_planOpen) ...[
                      const SizedBox(height: Space.s3),
                      for (final (i, entry) in message.toolTrace.indexed) ...[
                        if (i > 0) const SizedBox(height: Space.s2),
                        Text(
                          entry.display,
                          style: MemoraText.style(
                            11,
                            height: 1.5,
                            spacing: 0.2,
                            color: c.accentInk,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
        if (sources.isNotEmpty) ...[
          const SizedBox(height: Space.s4),
          Padding(
            padding: const EdgeInsets.only(left: _answerIndent),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CapsLabel(
                  presentation.sourceLabel ?? memoryCount(sources.length),
                ),
                const SizedBox(height: Space.s3),
                if (presentation.layout == SourceLayout.table)
                  _SourceTable(
                    sources: sources,
                    attribute: presentation.tableAttribute ?? 'amount',
                    highlight: presentation.highlightMemoryId,
                  )
                else
                  _SourceStrip(sources: sources),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Caption under a headline figure, if the answer was checked.
String? headlineNote(MessagePresentation presentation) {
  if (presentation.headlineNote != null) return presentation.headlineNote;
  return switch (presentation.verification) {
    VerificationState.verified => 'Verified against the original image',
    VerificationState.corrected => 'Corrected after checking the image',
    VerificationState.none => null,
  };
}

/// The value shown for a source: the answer's attribute, else its key fact.
String sourceValue(MemoryDetails details, String attribute) {
  for (final a in details.attributes) {
    if (a.type == attribute) return a.value;
  }
  return keyFact(details) ?? humanizeKey(details.memory.category ?? 'memory');
}

/// The month a source belongs to: its first dated fact, else when it was
/// taken.
String sourceMonth(MemoryDetails details) {
  for (final a in details.attributes) {
    final iso = a.valueDate;
    if (iso != null) {
      final date = DateTime.tryParse(iso);
      if (date != null) return DateFormat('MMM y').format(date);
    }
  }
  return DateFormat('MMM y').format(details.memory.takenAt);
}

class _SourceStrip extends StatelessWidget {
  const _SourceStrip({required this.sources});

  final List<MemoryDetails> sources;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 96 + Space.s2 + 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sources.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.s3),
        itemBuilder: (context, i) {
          final details = sources[i];
          return TapArea(
            onTap: () => context.push(Routes.memory(details.memory.id)),
            semanticLabel: memoryTitle(details.memory),
            minSize: 0,
            child: SizedBox(
              width: 76,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 96,
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                      foregroundDecoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Radii.sm),
                        border: Border.all(color: c.lineSoft),
                      ),
                      child: MemoryImageView(
                        path: details.memory.thumbnailPath,
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.s2),
                  Text(
                    sourceValue(details, 'amount'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MemoraText.style(
                      10,
                      medium: true,
                      tabular: true,
                      color: c.text,
                    ),
                  ),
                  CapsLabel(
                    sourceMonth(details),
                    size: 9,
                    spacing: 0.6,
                    color: c.dim,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SourceTable extends StatelessWidget {
  const _SourceTable({
    required this.sources,
    required this.attribute,
    required this.highlight,
  });

  final List<MemoryDetails> sources;
  final String attribute;
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          Container(
            color: c.surface2,
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s4,
              vertical: 7,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: CapsLabel('Month', size: 8.5, spacing: 1.1),
                ),
                SizedBox(
                  width: 62,
                  child: CapsLabel(
                    sentenceCase(attribute),
                    size: 8.5,
                    spacing: 1.1,
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 30),
              ],
            ),
          ),
          Container(height: 1, color: c.line),
          for (final (i, details) in sources.indexed)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == sources.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: c.lineSoft)),
              ),
              child: TapArea(
                onTap: () => context.push(Routes.memory(details.memory.id)),
                semanticLabel: memoryTitle(details.memory),
                minSize: 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.s4,
                    vertical: Space.s3,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          sourceMonth(details),
                          style: MemoraText.style(12.5, color: c.text),
                        ),
                      ),
                      SizedBox(
                        width: 62,
                        child: Text(
                          sourceValue(details, attribute),
                          textAlign: TextAlign.right,
                          style: MemoraText.style(
                            12.5,
                            medium: true,
                            tabular: true,
                            color: details.memory.id == highlight
                                ? c.accentInk
                                : c.text,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 30,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Icon(
                            MemoraIcons.image,
                            size: 13,
                            color: c.dim,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
