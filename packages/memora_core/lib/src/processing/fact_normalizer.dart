import '../model/details.dart';
import '../model/understanding.dart';
import '../ports/stores.dart';
import '../text/amounts.dart';
import '../text/dates.dart';
import '../text/money_format.dart';
import '../text/normalize.dart';

/// Turns what a vision capability returned into typed facts ready to store.
///
/// Amounts get a numeric value and an ISO currency, dates become
/// `YYYY-MM-DD`, entities get a folded form for matching, and duplicates are
/// removed. See docs/architecture.md, section 5.3.
class FactNormalizer {
  const FactNormalizer();

  /// Attribute types whose value is a plain number worth storing as one.
  static const numericAttributeTypes = {'quantity', 'percentage'};

  static const maxKeywords = 20;

  /// Normalizes [u]. [defaultCurrency] fills in amounts that came without
  /// one. [takenAt] resolves dates written without a year, so it is given
  /// rather than guessed from the current time.
  NormalizedFacts normalize(
    MemoryUnderstanding u, {
    required DateTime takenAt,
    String defaultCurrency = 'INR',
  }) {
    return NormalizedFacts(
      entities: _entities(u.entities),
      attributes: [
        ..._amounts(u.amounts, defaultCurrency.toUpperCase()),
        ..._dates(u.dates, takenAt),
        ..._others(u.attributes),
      ],
      keywords: _keywords(u.keywords),
    );
  }

  List<StoredEntity> _entities(List<EntityMention> mentions) {
    final seen = <String>{};
    final result = <StoredEntity>[];
    for (final mention in mentions) {
      final value = mention.value.trim();
      if (value.isEmpty) continue;
      final folded = foldForMatch(value);
      if (!seen.add('${mention.type}|$folded')) continue;
      result.add(
        StoredEntity(type: mention.type, value: value, normalizedValue: folded),
      );
    }
    return result;
  }

  List<StoredAttribute> _amounts(
    List<AmountMention> amounts,
    String defaultCurrency,
  ) {
    final seen = <String>{};
    final result = <StoredAttribute>[];
    for (final amount in amounts) {
      final value = amount.value.toDouble();
      if (!value.isFinite) continue;
      // A bare zero with nothing around it is usually a value the model left
      // out. A zero that came with a currency or a label, such as a balance
      // due of nothing, is worth keeping.
      if (value == 0 && amount.currency == null && amount.type == 'amount') {
        continue;
      }
      final currency = normalizeCurrency(amount.currency) ?? defaultCurrency;
      if (!seen.add('${amount.type}|$value|$currency')) continue;
      result.add(
        StoredAttribute(
          type: 'amount',
          label: amount.type,
          value: formatMoney(value, currency),
          valueNum: value,
          currency: currency,
        ),
      );
    }
    return result;
  }

  List<StoredAttribute> _dates(List<DateMention> dates, DateTime takenAt) {
    final seen = <String>{};
    final result = <StoredAttribute>[];
    for (final mention in dates) {
      final date = _parseDate(mention.value, takenAt);
      if (date == null) continue;
      final iso = isoDate(date);
      if (!seen.add('${mention.type}|$iso')) continue;
      result.add(
        StoredAttribute(
          type: mention.type,
          value: displayDate(date),
          valueDate: iso,
        ),
      );
    }
    return result;
  }

  DateTime? _parseDate(String value, DateTime takenAt) {
    final iso = parseIsoDate(value);
    if (iso != null) return iso;
    final found = findDates(value, reference: takenAt);
    return found.length == 1 ? found.single.date : null;
  }

  List<StoredAttribute> _others(List<AttributeMention> attributes) {
    final seen = <String>{};
    final result = <StoredAttribute>[];
    for (final attribute in attributes) {
      final value = attribute.value.trim();
      if (value.isEmpty) continue;
      if (!seen.add('${attribute.type}|$value')) continue;
      result.add(
        StoredAttribute(
          type: attribute.type,
          value: value,
          valueNum: numericAttributeTypes.contains(attribute.type)
              ? _plainNumber(value)
              : null,
        ),
      );
    }
    return result;
  }

  static final _plainNumberPattern = RegExp(r'^(-?\d[\d,]*(?:\.\d+)?)\s*%?$');

  double? _plainNumber(String value) {
    final match = _plainNumberPattern.firstMatch(value);
    if (match == null) return null;
    return double.tryParse(match[1]!.replaceAll(',', ''));
  }

  List<String> _keywords(List<String> keywords) {
    final seen = <String>{};
    for (final keyword in keywords) {
      final k = keyword.trim().toLowerCase();
      if (k.isEmpty) continue;
      seen.add(k);
      if (seen.length == maxKeywords) break;
    }
    return seen.toList();
  }
}
