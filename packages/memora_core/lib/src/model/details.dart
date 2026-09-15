import 'package:meta/meta.dart';

import 'memory.dart';
import 'processing.dart';

/// An entity row as stored, with its normalized form for matching.
@immutable
class StoredEntity {
  const StoredEntity({
    required this.type,
    required this.value,
    required this.normalizedValue,
  });

  final String type;
  final String value;
  final String normalizedValue;
}

/// An attribute row as stored. Typed columns make range queries possible.
@immutable
class StoredAttribute {
  const StoredAttribute({
    required this.type,
    required this.value,
    this.valueNum,
    this.valueDate,
    this.currency,
    this.label,
  });

  /// For example `amount`, `due_date`, `invoice_number`, `url`.
  final String type;

  /// The value as shown to the user, for example `₹1,842`.
  final String value;

  /// Numeric value when the attribute is a number or amount.
  final double? valueNum;

  /// `YYYY-MM-DD` when the attribute is a date.
  final String? valueDate;

  /// ISO 4217 code for amounts.
  final String? currency;

  /// Sub-type from the model, for example `total` for an amount.
  final String? label;
}

/// Everything shown on the memory detail screen.
@immutable
class MemoryDetails {
  const MemoryDetails({
    required this.memory,
    required this.entities,
    required this.attributes,
    required this.keywords,
    required this.processing,
    required this.conversationCount,
  });

  final Memory memory;
  final List<StoredEntity> entities;
  final List<StoredAttribute> attributes;
  final List<String> keywords;

  /// Newest first.
  final List<ProcessingRecord> processing;

  /// How many conversations cite this memory.
  final int conversationCount;
}
