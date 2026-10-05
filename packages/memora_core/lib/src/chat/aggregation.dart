import 'package:meta/meta.dart';

import '../ports/stores.dart';
import '../text/dates.dart';
import '../text/money_format.dart';
import 'query_parser.dart';

/// Why an aggregate has no value.
enum AggregateProblem {
  /// None of the memories have the attribute.
  noValues,

  /// The attribute holds dates, which can't be summed or averaged.
  notNumeric,
}

/// The result of running an [AggregateOp] over some memories.
@immutable
class AggregateOutcome {
  const AggregateOutcome({
    required this.op,
    required this.memoryIds,
    this.attribute,
    this.value,
    this.display,
    this.currency,
    this.memoryId,
    this.skipped = 0,
    this.problem,
  });

  final AggregateOp op;

  /// Null for a plain count or latest over memories.
  final String? attribute;

  /// The numeric result. Null for date results.
  final double? value;

  /// The result as shown to the user, for example `₹2,103`.
  final String? display;
  final String? currency;

  /// The single memory behind a max, min or latest.
  final String? memoryId;

  /// Every memory whose value went into the result.
  final List<String> memoryIds;

  /// Values left out because they were in another currency.
  final int skipped;
  final AggregateProblem? problem;

  bool get hasValue => display != null;

  /// The JSON returned to the chat model by `aggregate_results`.
  Map<String, Object?> toToolJson() => {
    'op': op.name,
    'attribute': ?attribute,
    'value': ?_jsonNumber(value),
    'display': ?display,
    'currency': ?currency,
    if (op == AggregateOp.max ||
        op == AggregateOp.min ||
        op == AggregateOp.latest)
      'memory_id': ?memoryId,
    if (op == AggregateOp.sum || op == AggregateOp.avg) 'memory_ids': memoryIds,
    if (skipped > 0) 'skipped_other_currency': skipped,
  };

  static Object? _jsonNumber(double? value) {
    if (value == null) return null;
    return value == value.roundToDouble() ? value.round() : value;
  }
}

/// Labels that mark the amount to use when a memory has several, so a
/// receipt's subtotal or tax never stands in for what it cost.
const preferredAmountLabels = [
  'total',
  'grand_total',
  'amount_due',
  'total_due',
  'payable',
  'net_payable',
  'balance_due',
];

/// The one value a memory contributes: the one labeled as a total when there
/// is one, otherwise the first. Null when [values] is empty.
AttributeValue? preferredValue(Iterable<AttributeValue> values) {
  AttributeValue? best;
  for (final value in values) {
    if (best == null ||
        (!preferredAmountLabels.contains(best.attribute.label) &&
            preferredAmountLabels.contains(value.attribute.label))) {
      best = value;
    }
  }
  return best;
}

/// Computes aggregates over memories using stored attribute values.
///
/// Each memory contributes one value: the one labeled as a total when there
/// is one, otherwise the first. Money is only combined within the most common
/// currency, and the rest are counted as skipped.
class Aggregator {
  const Aggregator(this._search);

  final SearchStore _search;

  Future<AggregateOutcome> run(
    List<String> ids,
    AggregateOp op, {
    String? attribute,
  }) async {
    final unique = <String>{...ids}.toList();

    if (attribute == null && op == AggregateOp.count) {
      return AggregateOutcome(
        op: op,
        value: unique.length.toDouble(),
        display: '${unique.length}',
        memoryIds: unique,
      );
    }
    if (attribute == null && op == AggregateOp.latest) {
      final cards = await _search.cards(unique);
      if (cards.isEmpty) {
        return AggregateOutcome(
          op: op,
          memoryIds: const [],
          problem: AggregateProblem.noValues,
        );
      }
      var newest = cards.first;
      for (final card in cards.skip(1)) {
        if (card.takenAt.isAfter(newest.takenAt)) newest = card;
      }
      return AggregateOutcome(
        op: op,
        display: displayDate(newest.takenAt),
        memoryId: newest.id,
        memoryIds: [newest.id],
      );
    }

    final type = attribute ?? 'amount';
    final byMemory = <String, List<AttributeValue>>{};
    for (final value in await _search.attributeValues(unique, type)) {
      (byMemory[value.memoryId] ??= []).add(value);
    }
    final values = [
      for (final id in unique) ?preferredValue(byMemory[id] ?? const []),
    ];
    if (values.isEmpty) {
      return AggregateOutcome(
        op: op,
        attribute: type,
        memoryIds: const [],
        problem: AggregateProblem.noValues,
      );
    }

    if (op == AggregateOp.count) {
      return AggregateOutcome(
        op: op,
        attribute: type,
        value: values.length.toDouble(),
        display: '${values.length}',
        memoryIds: [for (final v in values) v.memoryId],
      );
    }
    if (op == AggregateOp.latest) {
      var newest = values.first;
      for (final v in values.skip(1)) {
        if (v.takenAt.isAfter(newest.takenAt)) newest = v;
      }
      return AggregateOutcome(
        op: op,
        attribute: type,
        value: newest.attribute.valueNum,
        display: newest.attribute.value,
        currency: newest.attribute.currency,
        memoryId: newest.memoryId,
        memoryIds: [newest.memoryId],
      );
    }

    final numeric = values.where((v) => v.attribute.valueNum != null).toList();
    if (numeric.isEmpty) return _dates(values, op, type);

    final byCurrency = <String?, int>{};
    for (final v in numeric) {
      final c = v.attribute.currency;
      byCurrency[c] = (byCurrency[c] ?? 0) + 1;
    }
    String? currency;
    var best = -1;
    for (final entry in byCurrency.entries) {
      if (entry.value > best) {
        best = entry.value;
        currency = entry.key;
      }
    }
    final chosen = [
      for (final v in numeric)
        if (v.attribute.currency == currency) v,
    ];
    final skipped = numeric.length - chosen.length;

    String format(double value) => type == 'amount' || currency != null
        ? formatMoney(value, currency)
        : formatNumber(value);

    switch (op) {
      case AggregateOp.max || AggregateOp.min:
        var winner = chosen.first;
        for (final v in chosen.skip(1)) {
          final better = op == AggregateOp.max
              ? v.attribute.valueNum! > winner.attribute.valueNum!
              : v.attribute.valueNum! < winner.attribute.valueNum!;
          if (better) winner = v;
        }
        return AggregateOutcome(
          op: op,
          attribute: type,
          value: winner.attribute.valueNum,
          display: format(winner.attribute.valueNum!),
          currency: currency,
          memoryId: winner.memoryId,
          memoryIds: [winner.memoryId],
          skipped: skipped,
        );
      case AggregateOp.sum || AggregateOp.avg:
        final total = chosen.fold(0.0, (sum, v) => sum + v.attribute.valueNum!);
        final result = op == AggregateOp.sum
            ? total
            : (total / chosen.length * 100).roundToDouble() / 100;
        return AggregateOutcome(
          op: op,
          attribute: type,
          value: result,
          display: format(result),
          currency: currency,
          memoryIds: [for (final v in chosen) v.memoryId],
          skipped: skipped,
        );
      case AggregateOp.count || AggregateOp.latest:
        throw StateError('handled above');
    }
  }

  AggregateOutcome _dates(
    List<AttributeValue> values,
    AggregateOp op,
    String type,
  ) {
    final dated = values.where((v) => v.attribute.valueDate != null).toList();
    if (dated.isEmpty || op == AggregateOp.sum || op == AggregateOp.avg) {
      return AggregateOutcome(
        op: op,
        attribute: type,
        memoryIds: const [],
        problem: dated.isEmpty
            ? AggregateProblem.noValues
            : AggregateProblem.notNumeric,
      );
    }
    var winner = dated.first;
    for (final v in dated.skip(1)) {
      final compare = v.attribute.valueDate!.compareTo(
        winner.attribute.valueDate!,
      );
      if (op == AggregateOp.max ? compare > 0 : compare < 0) winner = v;
    }
    return AggregateOutcome(
      op: op,
      attribute: type,
      display: winner.attribute.value,
      memoryId: winner.memoryId,
      memoryIds: [winner.memoryId],
    );
  }
}
