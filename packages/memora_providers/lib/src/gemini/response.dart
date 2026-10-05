import 'package:memora_core/memora_core.dart';

import '../shared/json_read.dart';

/// Finish reasons that mean Gemini withheld the answer.
const blockedFinishReasons = {
  'SAFETY',
  'RECITATION',
  'BLOCKLIST',
  'PROHIBITED_CONTENT',
  'SPII',
  'IMAGE_SAFETY',
  'IMAGE_PROHIBITED_CONTENT',
};

/// The first candidate of a `generateContent` response.
///
/// Throws [AiContentException] when the prompt itself was blocked.
Map<String, Object?>? firstCandidate(Map<String, Object?> json) {
  final blockReason = asString(
    asObject(json['promptFeedback'])?['blockReason'],
  );
  if (blockReason != null) {
    throw AiContentException(
      'Gemini blocked this request ($blockReason)',
      providerId: 'gemini',
    );
  }
  final candidates = asList(json['candidates']);
  return candidates.isEmpty ? null : asObject(candidates.first);
}

List<Object?> candidateParts(Map<String, Object?> candidate) =>
    asList(asObject(candidate['content'])?['parts']);

/// Answer text from [parts], leaving out thought summaries.
String partsText(List<Object?> parts) {
  final buffer = StringBuffer();
  for (final raw in parts) {
    final part = asObject(raw);
    if (part == null || part['thought'] == true) continue;
    final text = asString(part['text']);
    if (text != null) buffer.write(text);
  }
  return buffer.toString();
}

/// Model ids may be given as `models/gemini-2.5-flash`.
String bareModelId(String modelId) =>
    modelId.startsWith('models/') ? modelId.substring(7) : modelId;
