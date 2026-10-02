import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

void main() {
  test('parses the documented vision shape', () {
    final u = MemoryUnderstanding.fromJson({
      'summary': ' Reliance electricity bill for August 2026 ',
      'category': 'utility_bill',
      'visual_description': 'A utility bill displayed in a mobile app.',
      'extracted_text': 'Amount due Rs 1,842',
      'keywords': ['Reliance', 'electricity', 'bill', 'reliance', ''],
      'entities': [
        {'type': 'company', 'value': 'Reliance'},
        {'type': 'person', 'value': '  '},
      ],
      'dates': [
        {'type': 'Due Date', 'value': '2026-08-31'},
      ],
      'amounts': [
        {'type': 'total', 'value': 1842, 'currency': 'inr'},
      ],
      'attributes': [
        {'type': 'account_number', 'value': '•••• 4471'},
      ],
      'confidence': 0.86,
    });

    expect(u.summary, 'Reliance electricity bill for August 2026');
    expect(u.category, 'utility_bill');
    expect(u.keywords, ['reliance', 'electricity', 'bill']);
    expect(u.entities, [
      const EntityMention(type: 'company', value: 'Reliance'),
    ]);
    expect(u.dates.single.type, 'due_date');
    expect(
      u.amounts.single,
      const AmountMention(type: 'total', value: 1842, currency: 'INR'),
    );
    expect(u.attributes.single.value, '•••• 4471');
    expect(u.confidence, 0.86);
  });

  test('tolerates missing fields and wrong types', () {
    final u = MemoryUnderstanding.fromJson({
      'summary': 42,
      'category': 'Social Post!',
      'keywords': 'not a list',
      'entities': [
        'bad',
        {'value': 'Flutter'},
      ],
      'amounts': [
        {'value': '1,24,900', 'currency': 'INR'},
      ],
      'confidence': 3,
    });

    expect(u.summary, '42');
    expect(u.category, 'social_post');
    expect(u.keywords, isEmpty);
    expect(
      u.entities.single,
      const EntityMention(type: 'other', value: 'Flutter'),
    );
    expect(u.amounts.single.value, 124900);
    expect(u.amounts.single.type, 'amount');
    expect(u.confidence, 1.0);
  });

  test('round-trips through JSON', () {
    const u = MemoryUnderstanding(
      summary: 'Flight BLR to GOA',
      category: 'booking',
      keywords: ['flight'],
      entities: [EntityMention(type: 'organization', value: 'IndiGo')],
      dates: [DateMention(type: 'departure', value: '2026-10-18')],
      amounts: [AmountMention(type: 'total', value: 5400, currency: 'INR')],
      attributes: [
        AttributeMention(type: 'booking_reference', value: 'K4T9RB'),
      ],
    );
    final back = MemoryUnderstanding.fromJson(u.toJson());
    expect(back.toJson(), u.toJson());
  });

  test('normalizeKey produces snake_case', () {
    expect(normalizeKey('Due Date'), 'due_date');
    expect(normalizeKey('  --  '), 'other');
    expect(normalizeKey('PNR/Booking-Ref'), 'pnr_booking_ref');
  });
}
