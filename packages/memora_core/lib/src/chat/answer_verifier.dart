import 'package:meta/meta.dart';

import '../ai/capabilities.dart';
import '../ai/router.dart';
import '../ai/settings.dart';
import '../model/conversation.dart';
import '../ports/platform.dart';
import '../ports/stores.dart';
import 'presentation_builder.dart';

@immutable
class VerifiedAnswer {
  const VerifiedAnswer({required this.text, required this.presentation});

  final String text;
  final MessagePresentation presentation;
}

/// Checks a single figure against the original image with the vision
/// capability. See docs/architecture.md, section 9.4.
class AnswerVerifier {
  const AnswerVerifier({
    required this._router,
    required this._memories,
    required this._images,
    required this._aiSettings,
  });

  static const verifiedNote = 'Verified against the original image';
  static const correctedNote = 'Corrected after checking the original image';

  /// How long a corrected value may be. A figure is short. A sentence is a
  /// model explaining itself, and that does not belong in a headline.
  static const maxObservedLength = 40;

  static final _alphanumeric = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// True when what vision read back is short, on one line, and has
  /// something in it worth showing.
  static bool looksLikeValue(String observed) =>
      observed.isNotEmpty &&
      observed.length <= maxObservedLength &&
      !observed.contains('\n') &&
      observed.split(RegExp(r'\s+')).length <= 6 &&
      _alphanumeric.hasMatch(observed);

  final CapabilityRouter _router;
  final MemoryStore _memories;
  final ImageFiles _images;
  final AiSettingsRepository _aiSettings;

  /// Returns the answer as it stands when there is nothing to check, the
  /// user turned checking off, vision is unavailable, or the check fails.
  Future<VerifiedAnswer> verify({
    required String text,
    required MessagePresentation presentation,
    HeadlineSource? source,
  }) async {
    if (source == null) {
      return VerifiedAnswer(text: text, presentation: presentation);
    }
    try {
      final settings = await _aiSettings.load();
      if (!settings.verifyAnswers) {
        return VerifiedAnswer(text: text, presentation: presentation);
      }
      final vision = await _router.vision();
      final memory = await _memories.getMemory(source.memoryId);
      if (memory == null) {
        return VerifiedAnswer(text: text, presentation: presentation);
      }
      final bytes = await _images.readBytes(memory.imagePath);
      final result = await vision.service.verify(
        VerificationRequest(
          imageBytes: bytes,
          mimeType: memory.mimeType,
          absoluteImagePath: _images.absolutePath(memory.imagePath),
          attributeType: source.attributeType,
          expectedValue: source.value,
        ),
      );
      if (result.confirmed) {
        return VerifiedAnswer(
          text: text,
          presentation: _copy(
            presentation,
            verification: VerificationState.verified,
            headlineNote: verifiedNote,
          ),
        );
      }
      final observed = result.observedValue?.trim();
      if (observed == null ||
          observed == source.value ||
          !looksLikeValue(observed)) {
        return VerifiedAnswer(text: text, presentation: presentation);
      }
      return VerifiedAnswer(
        text:
            '$text The original image shows $observed, so I corrected the '
            'figure.',
        presentation: _copy(
          presentation,
          verification: VerificationState.corrected,
          headlineNote: correctedNote,
          headline: observed,
        ),
      );
    } on Object {
      // Verification is a bonus. Anything that goes wrong leaves the answer
      // exactly as the model wrote it.
      return VerifiedAnswer(text: text, presentation: presentation);
    }
  }

  MessagePresentation _copy(
    MessagePresentation p, {
    required VerificationState verification,
    required String headlineNote,
    String? headline,
  }) => MessagePresentation(
    layout: p.layout,
    headline: headline ?? p.headline,
    headlineNote: headlineNote,
    tableAttribute: p.tableAttribute,
    highlightMemoryId: p.highlightMemoryId,
    sourceLabel: p.sourceLabel,
    verification: verification,
    searchOnly: p.searchOnly,
  );
}
