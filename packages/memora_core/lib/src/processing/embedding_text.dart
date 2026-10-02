import '../model/details.dart';
import '../model/understanding.dart';
import '../ports/stores.dart';

/// How much extracted text goes into the embedding input.
const embeddingTextChars = 600;

/// The text sent to the embedding model for one memory, built from the
/// understanding rather than raw OCR. See docs/architecture.md, section 7.5.
///
/// Sections with nothing in them are left out. Extracted text has its
/// whitespace collapsed before the first 600 characters are taken.
String buildEmbeddingText(MemoryUnderstanding u, NormalizedFacts facts) {
  return _build(
    summary: u.summary,
    category: u.category,
    visualDescription: u.visualDescription,
    extractedText: u.extractedText,
    facts: facts,
  );
}

/// Rebuilds the embedding text from what is stored for a memory, for
/// reindexing after the embedding model changes.
String embeddingTextForDetails(MemoryDetails details) {
  final memory = details.memory;
  return _build(
    summary: memory.summary ?? '',
    category: memory.category ?? '',
    visualDescription: memory.visualDescription ?? '',
    extractedText: memory.extractedText ?? '',
    facts: NormalizedFacts(
      entities: details.entities,
      attributes: details.attributes,
      keywords: details.keywords,
    ),
  );
}

String _build({
  required String summary,
  required String category,
  required String visualDescription,
  required String extractedText,
  required NormalizedFacts facts,
}) {
  final text = extractedText.replaceAll(RegExp(r'\s+'), ' ').trim();
  final lines = <String>[
    summary.trim(),
    if (category.trim().isNotEmpty) 'Category: ${category.trim()}',
    visualDescription.trim(),
    if (facts.entities.isNotEmpty)
      'Entities: ${facts.entities.map((e) => e.value).join(', ')}',
    if (facts.keywords.isNotEmpty) 'Keywords: ${facts.keywords.join(', ')}',
    if (facts.attributes.isNotEmpty)
      'Facts: ${facts.attributes.map((a) => '${a.type}: ${a.value}').join('; ')}',
    if (text.isNotEmpty)
      'Text: ${text.length > embeddingTextChars ? text.substring(0, embeddingTextChars) : text}',
  ];
  return lines.where((line) => line.isNotEmpty).join('\n');
}
