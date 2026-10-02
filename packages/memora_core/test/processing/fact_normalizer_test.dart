import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

Map<String, Object?> _attr(StoredAttribute a) => {
  'type': a.type,
  'value': a.value,
  'num': a.valueNum,
  'date': a.valueDate,
  'currency': a.currency,
  'label': a.label,
};

Map<String, Object?> _entity(StoredEntity e) => {
  'type': e.type,
  'value': e.value,
  'normalized': e.normalizedValue,
};

void main() {
  const normalizer = FactNormalizer();

  test('normalizes the documented vision example', () {
    final u = MemoryUnderstanding.fromJson({
      'summary': 'Reliance electricity bill for August 2026',
      'category': 'utility_bill',
      'visual_description': 'A utility bill displayed in a mobile app.',
      'extracted_text': 'Amount due Rs 1,842',
      'keywords': ['reliance', 'electricity', 'bill'],
      'entities': [
        {'type': 'company', 'value': 'Reliance'},
      ],
      'dates': [
        {'type': 'due_date', 'value': '2026-08-31'},
      ],
      'amounts': [
        {'type': 'total', 'value': 1842, 'currency': 'INR'},
      ],
      'attributes': [
        {'type': 'account_number', 'value': '•••• 4471'},
      ],
      'confidence': 0.86,
    });

    final facts = normalizer.normalize(u);

    expect(facts.entities.map(_entity), [
      {'type': 'company', 'value': 'Reliance', 'normalized': 'reliance'},
    ]);
    expect(facts.attributes.map(_attr), [
      {
        'type': 'amount',
        'value': '₹1,842',
        'num': 1842.0,
        'date': null,
        'currency': 'INR',
        'label': 'total',
      },
      {
        'type': 'due_date',
        'value': '31 Aug 2026',
        'num': null,
        'date': '2026-08-31',
        'currency': null,
        'label': null,
      },
      {
        'type': 'account_number',
        'value': '•••• 4471',
        'num': null,
        'date': null,
        'currency': null,
        'label': null,
      },
    ]);
    expect(facts.keywords, ['reliance', 'electricity', 'bill']);
  });

  test('collapses duplicate entities by type and folded value', () {
    const u = MemoryUnderstanding(
      summary: 's',
      category: 'other',
      entities: [
        EntityMention(type: 'company', value: 'Café Coffee Day'),
        EntityMention(type: 'company', value: 'cafe  coffee day'),
        EntityMention(type: 'place', value: 'Cafe Coffee Day'),
        EntityMention(type: 'person', value: '   '),
      ],
    );

    final facts = normalizer.normalize(u);

    expect(facts.entities.map(_entity), [
      {
        'type': 'company',
        'value': 'Café Coffee Day',
        'normalized': 'cafe coffee day',
      },
      {
        'type': 'place',
        'value': 'Cafe Coffee Day',
        'normalized': 'cafe coffee day',
      },
    ]);
  });

  test('drops dates that do not parse and reads common formats', () {
    const u = MemoryUnderstanding(
      summary: 's',
      category: 'other',
      dates: [
        DateMention(type: 'due_date', value: '2026-13-01'),
        DateMention(type: 'event_date', value: 'soon'),
        DateMention(type: 'departure_date', value: '18 Oct 2026'),
        DateMention(type: 'departure_date', value: '2026-10-18'),
      ],
    );

    final facts = normalizer.normalize(u, takenAt: DateTime(2026, 9, 1));

    expect(facts.attributes.map(_attr), [
      {
        'type': 'departure_date',
        'value': '18 Oct 2026',
        'num': null,
        'date': '2026-10-18',
        'currency': null,
        'label': null,
      },
    ]);
  });

  test('amounts use the default currency and normalize symbols', () {
    const u = MemoryUnderstanding(
      summary: 's',
      category: 'receipt',
      amounts: [
        AmountMention(type: 'total', value: 12.5),
        AmountMention(type: 'price', value: 99, currency: r'$'),
        AmountMention(type: 'amount', value: 0),
      ],
    );

    final facts = normalizer.normalize(u, defaultCurrency: 'EUR');

    expect(facts.attributes.map((a) => (a.value, a.currency, a.label)), [
      ('€12.50', 'EUR', 'total'),
      (r'$99', 'USD', 'price'),
    ]);
  });

  test('quantity and percentage attributes get a numeric value', () {
    const u = MemoryUnderstanding(
      summary: 's',
      category: 'receipt',
      attributes: [
        AttributeMention(type: 'quantity', value: '3'),
        AttributeMention(type: 'percentage', value: '18%'),
        AttributeMention(type: 'quantity', value: 'a few'),
        AttributeMention(type: 'invoice_number', value: '1234'),
      ],
    );

    final facts = normalizer.normalize(u);

    expect(facts.attributes.map((a) => (a.type, a.valueNum)), [
      ('quantity', 3.0),
      ('percentage', 18.0),
      ('quantity', null),
      ('invoice_number', null),
    ]);
  });

  test('keywords are lowercase, trimmed, unique and capped at 20', () {
    final u = MemoryUnderstanding(
      summary: 's',
      category: 'other',
      keywords: [' Bill ', 'bill', '', for (var i = 0; i < 30; i++) 'k$i'],
    );

    final facts = normalizer.normalize(u);

    expect(facts.keywords.first, 'bill');
    expect(facts.keywords, hasLength(20));
    expect(facts.keywords.toSet(), hasLength(20));
  });
}
