import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

void main() {
  const normalizer = FactNormalizer();
  final takenAt = DateTime(2026, 9, 1);

  test('builds every section in order', () {
    const u = MemoryUnderstanding(
      summary: 'Reliance electricity bill for August 2026',
      category: 'utility_bill',
      visualDescription: 'A utility bill displayed in a mobile app.',
      extractedText: 'Reliance Energy\nAmount due   Rs 1,842',
      keywords: ['reliance', 'electricity', 'bill'],
      entities: [EntityMention(type: 'company', value: 'Reliance')],
      dates: [DateMention(type: 'due_date', value: '2026-08-31')],
      amounts: [AmountMention(type: 'total', value: 1842, currency: 'INR')],
      attributes: [
        AttributeMention(type: 'account_number', value: '•••• 4471'),
      ],
    );

    final text = buildEmbeddingText(
      u,
      normalizer.normalize(u, takenAt: takenAt),
    );

    expect(
      text,
      'Reliance electricity bill for August 2026\n'
      'Category: utility_bill\n'
      'A utility bill displayed in a mobile app.\n'
      'Entities: Reliance\n'
      'Keywords: reliance, electricity, bill\n'
      'Facts: amount: ₹1,842; due_date: 31 Aug 2026; '
      'account_number: •••• 4471\n'
      'Text: Reliance Energy Amount due Rs 1,842',
    );
  });

  test('omits empty sections', () {
    const u = MemoryUnderstanding(summary: 'A sunset', category: 'other');

    final text = buildEmbeddingText(
      u,
      normalizer.normalize(u, takenAt: takenAt),
    );

    expect(text, 'A sunset\nCategory: other');
  });

  test('uses only the first 600 characters of extracted text', () {
    final u = MemoryUnderstanding(
      summary: '',
      category: 'document',
      extractedText: 'x' * 700,
    );

    final text = buildEmbeddingText(
      u,
      normalizer.normalize(u, takenAt: takenAt),
    );

    expect(text, 'Category: document\nText: ${'x' * 600}');
  });

  test('rebuilds the same text from stored details', () {
    const u = MemoryUnderstanding(
      summary: 'Flight to Goa',
      category: 'booking',
      visualDescription: 'Airline app booking screen.',
      extractedText: 'PNR K4T9RB',
      keywords: ['flight', 'goa'],
      entities: [EntityMention(type: 'company', value: 'IndiGo')],
      attributes: [
        AttributeMention(type: 'booking_reference', value: 'K4T9RB'),
      ],
    );
    final facts = normalizer.normalize(u, takenAt: takenAt);
    final details = MemoryDetails(
      memory: Memory(
        id: 'm1',
        imagePath: 'originals/m1.png',
        source: MemorySource.gallery,
        sha256: 'abc',
        mimeType: 'image/png',
        width: 1,
        height: 1,
        byteSize: 1,
        takenAt: DateTime(2026, 9, 1),
        addedAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
        status: ProcessingStatus.ready,
        summary: u.summary,
        category: u.category,
        visualDescription: u.visualDescription,
        extractedText: u.extractedText,
      ),
      entities: facts.entities,
      attributes: facts.attributes,
      keywords: facts.keywords,
      processing: const [],
      conversationCount: 0,
    );

    expect(embeddingTextForDetails(details), buildEmbeddingText(u, facts));
  });
}
