import 'package:meta/meta.dart';

import '../model/retrieval.dart';
import '../text/amounts.dart';
import '../text/category_words.dart';
import '../text/dates.dart';

/// Operations over an attribute in a set of memories.
enum AggregateOp { max, min, sum, avg, count, latest }

/// A superlative in a question, such as "highest" or "how many".
@immutable
class AggregateIntent {
  const AggregateIntent(this.op, {this.attribute = 'amount'});

  final AggregateOp op;
  final String attribute;

  @override
  bool operator ==(Object other) =>
      other is AggregateIntent &&
      other.op == op &&
      other.attribute == attribute;

  @override
  int get hashCode => Object.hash(op, attribute);

  @override
  String toString() => 'AggregateIntent(${op.name}, $attribute)';
}

/// What [QueryParser] understood in a question.
@immutable
class ParsedQuery {
  const ParsedQuery({
    required this.query,
    required this.remainingText,
    this.aggregate,
  });

  final RetrievalQuery query;
  final AggregateIntent? aggregate;

  /// Words left after dates, amounts, categories, superlatives and filler
  /// were taken out. Used for full-text and semantic search.
  final String remainingText;
}

/// Turns a plain-language question into a [RetrievalQuery] without a chat
/// model. See docs/architecture.md, section 9.2.
class QueryParser {
  const QueryParser({this.defaultCurrency = 'INR'});

  final String defaultCurrency;

  static const fillerWords = {
    'a',
    'all',
    'an',
    'and',
    'any',
    'are',
    'at',
    'by',
    'can',
    'did',
    'do',
    'does',
    'find',
    'for',
    'from',
    'get',
    'give',
    'had',
    'has',
    'have',
    'how',
    'i',
    'image',
    'images',
    'in',
    'is',
    'it',
    'its',
    'list',
    'me',
    'memories',
    'memory',
    'much',
    'my',
    'of',
    'on',
    'one',
    'ones',
    'or',
    'photo',
    'photos',
    'please',
    'saw',
    'screenshot',
    'screenshots',
    'see',
    'show',
    'some',
    'that',
    'the',
    'them',
    'these',
    'this',
    'those',
    'to',
    'was',
    'were',
    'what',
    'which',
    'with',
    'you',
  };

  /// Everyday words that name a category. See [categoryWordMap].
  static const categoryWords = categoryWordMap;

  static RegExp _words(String body) =>
      RegExp('(?<![a-z0-9])(?:$body)(?![a-z0-9])', caseSensitive: false);

  static final _amount = '($amountExpressionPattern)';
  static final _between = RegExp(
    '(?<![a-z])between\\s+$_amount\\s+(?:and|to)\\s+$_amount',
    caseSensitive: false,
  );
  static final _atLeast = RegExp(
    '(?:(?<![a-z])(?:over|above|more\\s+than|greater\\s+than|at\\s+least|'
    'exceeding|upwards\\s+of)\\s+|>=?\\s*)$_amount',
    caseSensitive: false,
  );
  static final _atMost = RegExp(
    '(?:(?<![a-z])(?:under|below|less\\s+than|at\\s+most|cheaper\\s+than|'
    'up\\s+to)\\s+|<=?\\s*)$_amount',
    caseSensitive: false,
  );
  static final _notMoney = RegExp(
    r'^\s*(?:\d|[.,]\d|days?\b|weeks?\b|months?\b|years?\b|hours?\b|hrs?\b|'
    r'mins?\b|minutes?\b|seconds?\b|items?\b|km\b|kms\b|kg\b|gb\b|mb\b|%)',
  );

  static const _weekdays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];
  static const _bareMonths =
      '(?:january|february|april|june|july|august|september|october|november|'
      'december|jan|feb|apr|jun|jul|aug|sept|sep|oct|nov|dec)';
  static const _prepositions = '(around|since|before|after|in|during|from)';

  static final _today = _words('today');
  static final _yesterday = _words('yesterday');
  static final _relativeUnit = _words(
    '(this|last|past|previous)\\s+(week|month|year)',
  );
  static final _lastN = _words(
    '(?:last|past|previous)\\s+(\\d{1,3})\\s+(days?|weeks?|months?)',
  );
  static final _lastWeekday = _words('last\\s+(${_weekdays.join('|')})');
  static final _monthYear = RegExp(
    '(?<![a-z])(?:$_prepositions\\s+)?($monthNamePattern)\\.?,?\\s+'
    '((?:19|20)\\d{2})(?![0-9])',
    caseSensitive: false,
  );
  static final _prepositionMonth = _words(
    '$_prepositions\\s+($monthNamePattern)',
  );
  static final _prepositionYear = RegExp(
    '(?<![a-z])$_prepositions\\s+((?:19|20)\\d{2})(?![0-9])',
    caseSensitive: false,
  );
  static final _bareMonth = _words('($_bareMonths)');

  static final _superlatives = <AggregateOp, RegExp>{
    AggregateOp.count: _words('how\\s+many|count|number\\s+of'),
    AggregateOp.avg: _words('average|avg|mean'),
    AggregateOp.sum: _words('total|sum|spent|spend|spending'),
    AggregateOp.max: _words(
      'highest|most\\s+expensive|largest|biggest|maximum|costliest|priciest',
    ),
    AggregateOp.min: _words(
      'lowest|cheapest|smallest|minimum|least\\s+expensive',
    ),
    AggregateOp.latest: _words('latest|most\\s+recent|last\\s+one|newest'),
  };

  static final _categoryPattern = _words(categoryWords.keys.join('|'));
  static final _wordPattern = RegExp(r'[\p{L}\p{M}\p{N}]+', unicode: true);

  ParsedQuery parse(String text, {required DateTime now}) {
    final scan = _Scan(text.toLowerCase());
    final attribute = _amountFilter(scan);
    final takenBetween = _dateRange(scan, now);
    final aggregate = _aggregate(scan);

    final categories = <String>{};
    for (final m in scan.matches(_categoryPattern)) {
      categories.addAll(categoryWords[m[0]!.toLowerCase()]!);
      scan.consume(m);
    }

    final remaining = [
      for (final m in _wordPattern.allMatches(scan.text))
        if (!scan.isConsumed(m) && !fillerWords.contains(m[0])) m[0]!,
    ].join(' ');

    return ParsedQuery(
      query: RetrievalQuery(
        text: remaining.isEmpty ? null : remaining,
        categories: categories,
        attributes: [?attribute],
        takenBetween: takenBetween,
        limit: aggregate == null ? 20 : RetrievalQuery.maxLimit,
      ),
      aggregate: aggregate,
      remainingText: remaining,
    );
  }

  ParsedAmount? _money(_Scan scan, Match m, int group) {
    final after = scan.text.substring(m.end);
    if (_notMoney.hasMatch(after)) return null;
    return parseAmountExpression(m[group]!, defaultCurrency: defaultCurrency);
  }

  AttributeFilter? _amountFilter(_Scan scan) {
    for (final m in scan.matches(_between)) {
      final low = parseAmountExpression(
        m[1]!,
        defaultCurrency: defaultCurrency,
      );
      final high = _money(scan, m, 2);
      if (low == null || high == null) continue;
      scan.consume(m);
      return AttributeFilter(
        type: 'amount',
        min: low.value,
        max: high.value,
        currency: high.currency ?? low.currency,
      );
    }
    double? min;
    double? max;
    String? currency;
    for (final m in scan.matches(_atLeast)) {
      final amount = _money(scan, m, 1);
      if (amount == null) continue;
      scan.consume(m);
      min = amount.value;
      currency ??= amount.currency;
      break;
    }
    for (final m in scan.matches(_atMost)) {
      final amount = _money(scan, m, 1);
      if (amount == null) continue;
      scan.consume(m);
      max = amount.value;
      currency ??= amount.currency;
      break;
    }
    if (min == null && max == null) return null;
    return AttributeFilter(
      type: 'amount',
      min: min,
      max: max,
      currency: currency,
    );
  }

  DateRange? _dateRange(_Scan scan, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);

    DateRange? take(RegExp pattern, DateRange? Function(Match m) build) {
      for (final m in scan.matches(pattern)) {
        final range = build(m);
        if (range == null) continue;
        scan.consume(m);
        return range;
      }
      return null;
    }

    return take(_today, (_) => DateRange.day(today)) ??
        take(
          _yesterday,
          (_) =>
              DateRange.day(DateTime(today.year, today.month, today.day - 1)),
        ) ??
        take(_relativeUnit, (m) => _relative(m[1]!, m[2]!, today)) ??
        take(_lastN, (m) => _lastCount(int.parse(m[1]!), m[2]!, today)) ??
        take(_lastWeekday, (m) {
          final weekday = _weekdays.indexOf(m[1]!) + 1;
          var back = (today.weekday - weekday) % 7;
          if (back == 0) back = 7;
          return DateRange.day(
            DateTime(today.year, today.month, today.day - back),
          );
        }) ??
        take(_monthYear, (m) {
          final month = monthNumber(m[2]!)!;
          return _aroundMonth(m[1], int.parse(m[3]!), month);
        }) ??
        take(_prepositionMonth, (m) {
          final month = monthNumber(m[2]!)!;
          return _aroundMonth(m[1], _recentYear(month, today), month);
        }) ??
        take(_prepositionYear, (m) {
          final year = int.parse(m[2]!);
          return switch (m[1]) {
            'since' => DateRange(start: DateTime(year)),
            'after' => DateRange(start: DateTime(year + 1)),
            'before' => DateRange(end: DateTime(year)),
            _ => DateRange.year(year),
          };
        }) ??
        take(_bareMonth, (m) {
          final month = monthNumber(m[1]!)!;
          return DateRange.month(_recentYear(month, today), month);
        });
  }

  DateRange? _relative(String which, String unit, DateTime today) {
    final previous = which != 'this';
    switch (unit) {
      case 'week':
        final monday = DateTime(
          today.year,
          today.month,
          today.day - (today.weekday - 1) - (previous ? 7 : 0),
        );
        return DateRange(
          start: monday,
          end: DateTime(monday.year, monday.month, monday.day + 7),
        );
      case 'month':
        return DateRange.month(today.year, today.month - (previous ? 1 : 0));
      case 'year':
        return DateRange.year(today.year - (previous ? 1 : 0));
    }
    return null;
  }

  DateRange _lastCount(int count, String unit, DateTime today) {
    final end = DateTime(today.year, today.month, today.day + 1);
    final start = switch (unit) {
      'day' ||
      'days' => DateTime(today.year, today.month, today.day - count + 1),
      'week' ||
      'weeks' => DateTime(today.year, today.month, today.day - count * 7 + 1),
      _ => DateTime(today.year, today.month - count, today.day + 1),
    };
    return DateRange(start: start, end: end);
  }

  /// The most recent year in which [month] has started by [today].
  int _recentYear(int month, DateTime today) =>
      month <= today.month ? today.year : today.year - 1;

  DateRange _aroundMonth(String? preposition, int year, int month) {
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1);
    return switch (preposition) {
      'around' => DateRange(
        start: DateTime(year, month, 1 - 15),
        end: DateTime(year, month + 1, 1 + 15),
      ),
      'since' => DateRange(start: start),
      'after' => DateRange(start: end),
      'before' => DateRange(end: start),
      _ => DateRange(start: start, end: end),
    };
  }

  AggregateIntent? _aggregate(_Scan scan) {
    AggregateOp? op;
    var earliest = scan.text.length + 1;
    for (final entry in _superlatives.entries) {
      for (final m in scan.matches(entry.value)) {
        if (m.start < earliest) {
          earliest = m.start;
          op = entry.key;
        }
        scan.consume(m);
      }
    }
    return op == null ? null : AggregateIntent(op);
  }
}

/// Lowercased question text with the character ranges already understood.
class _Scan {
  _Scan(this.text) : _consumed = List.filled(text.length, false);

  final String text;
  final List<bool> _consumed;

  bool isConsumed(Match m) {
    for (var i = m.start; i < m.end; i++) {
      if (_consumed[i]) return true;
    }
    return false;
  }

  List<RegExpMatch> matches(RegExp pattern) => [
    for (final m in pattern.allMatches(text))
      if (!isConsumed(m)) m,
  ];

  void consume(Match m) {
    for (var i = m.start; i < m.end; i++) {
      _consumed[i] = true;
    }
  }
}
