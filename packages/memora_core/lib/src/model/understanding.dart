import 'package:meta/meta.dart';

import '../util/json.dart';

/// A named thing seen in an image: a company, a person, a product.
@immutable
class EntityMention {
  const EntityMention({required this.type, required this.value});

  factory EntityMention.fromJson(Map<String, Object?> json) => EntityMention(
    type: normalizeKey(readString(json, 'type') ?? 'other'),
    value: readString(json, 'value') ?? '',
  );

  final String type;
  final String value;

  Map<String, Object?> toJson() => {'type': type, 'value': value};

  @override
  bool operator ==(Object other) =>
      other is EntityMention && other.type == type && other.value == value;

  @override
  int get hashCode => Object.hash(type, value);

  @override
  String toString() => '$type:$value';
}

/// A date that appears in the image content, such as a due date.
@immutable
class DateMention {
  const DateMention({required this.type, required this.value});

  factory DateMention.fromJson(Map<String, Object?> json) => DateMention(
    type: normalizeKey(readString(json, 'type') ?? 'date'),
    value: readString(json, 'value') ?? '',
  );

  final String type;

  /// As returned by the model. Normalization turns it into `YYYY-MM-DD`.
  final String value;

  Map<String, Object?> toJson() => {'type': type, 'value': value};

  @override
  bool operator ==(Object other) =>
      other is DateMention && other.type == type && other.value == value;

  @override
  int get hashCode => Object.hash(type, value);
}

/// A money amount that appears in the image content.
@immutable
class AmountMention {
  const AmountMention({required this.type, required this.value, this.currency});

  factory AmountMention.fromJson(Map<String, Object?> json) => AmountMention(
    type: normalizeKey(readString(json, 'type') ?? 'amount'),
    value: readNum(json, 'value') ?? 0,
    currency: readString(json, 'currency')?.toUpperCase(),
  );

  /// What the amount represents, for example `total` or `price`.
  final String type;
  final num value;

  /// ISO 4217 code when known.
  final String? currency;

  Map<String, Object?> toJson() => {
    'type': type,
    'value': value,
    'currency': ?currency,
  };

  @override
  bool operator ==(Object other) =>
      other is AmountMention &&
      other.type == type &&
      other.value == value &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(type, value, currency);
}

/// Any other typed fact: an invoice number, a URL, an address.
@immutable
class AttributeMention {
  const AttributeMention({required this.type, required this.value});

  factory AttributeMention.fromJson(Map<String, Object?> json) =>
      AttributeMention(
        type: normalizeKey(readString(json, 'type') ?? 'other'),
        value: readString(json, 'value') ?? '',
      );

  final String type;
  final String value;

  Map<String, Object?> toJson() => {'type': type, 'value': value};

  @override
  bool operator ==(Object other) =>
      other is AttributeMention && other.type == type && other.value == value;

  @override
  int get hashCode => Object.hash(type, value);
}

/// Categories vision adapters are asked to choose from. Anything else a model
/// returns is kept, normalized to snake_case.
const suggestedCategories = <String>[
  'utility_bill',
  'receipt',
  'invoice',
  'booking',
  'ticket',
  'product',
  'comparison',
  'place',
  'map',
  'chat',
  'social_post',
  'article',
  'document',
  'code',
  'reference',
  'event',
  'other',
];

/// What a vision capability understood about one image.
///
/// Every vision adapter produces this shape. See docs/architecture.md,
/// section 7.4.
@immutable
class MemoryUnderstanding {
  const MemoryUnderstanding({
    required this.summary,
    required this.category,
    this.visualDescription = '',
    this.extractedText = '',
    this.keywords = const [],
    this.entities = const [],
    this.dates = const [],
    this.amounts = const [],
    this.attributes = const [],
    this.confidence,
  });

  /// Parses model output leniently. Missing lists become empty, wrong types
  /// are skipped, and the category is normalized.
  factory MemoryUnderstanding.fromJson(Map<String, Object?> json) {
    final keywords = <String>{};
    for (final k in readList(json, 'keywords')) {
      if (k is String && k.trim().isNotEmpty) {
        keywords.add(k.trim().toLowerCase());
      }
    }
    final confidence = readNum(json, 'confidence')?.toDouble();
    return MemoryUnderstanding(
      summary: (readString(json, 'summary') ?? '').trim(),
      category: normalizeKey(readString(json, 'category') ?? 'other'),
      visualDescription: (readString(json, 'visual_description') ?? '').trim(),
      extractedText: readString(json, 'extracted_text') ?? '',
      keywords: keywords.toList(),
      entities: readObjects(json, 'entities')
          .map(EntityMention.fromJson)
          .where((e) => e.value.trim().isNotEmpty)
          .toList(),
      dates: readObjects(json, 'dates')
          .map(DateMention.fromJson)
          .where((d) => d.value.trim().isNotEmpty)
          .toList(),
      amounts: readObjects(
        json,
        'amounts',
      ).map(AmountMention.fromJson).toList(),
      attributes: readObjects(json, 'attributes')
          .map(AttributeMention.fromJson)
          .where((a) => a.value.trim().isNotEmpty)
          .toList(),
      confidence: confidence?.clamp(0.0, 1.0),
    );
  }

  final String summary;
  final String category;
  final String visualDescription;
  final String extractedText;
  final List<String> keywords;
  final List<EntityMention> entities;
  final List<DateMention> dates;
  final List<AmountMention> amounts;
  final List<AttributeMention> attributes;

  /// The model's own confidence from 0 to 1, when it gives one.
  final double? confidence;

  Map<String, Object?> toJson() => {
    'summary': summary,
    'category': category,
    'visual_description': visualDescription,
    'extracted_text': extractedText,
    'keywords': keywords,
    'entities': [for (final e in entities) e.toJson()],
    'dates': [for (final d in dates) d.toJson()],
    'amounts': [for (final a in amounts) a.toJson()],
    'attributes': [for (final a in attributes) a.toJson()],
    'confidence': ?confidence,
  };
}
