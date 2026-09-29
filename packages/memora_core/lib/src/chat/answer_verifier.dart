import 'package:meta/meta.dart';

import '../ai/capabilities.dart';
import '../ai/errors.dart';
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
      if (observed == null || observed.isEmpty || observed == source.value) {
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
    } on CapabilityUnavailableException {
      return VerifiedAnswer(text: text, presentation: presentation);
    } on AiException {
      return VerifiedAnswer(text: text, presentation: presentation);
    } on Exception {
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
