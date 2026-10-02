import 'dart:math' as math;

import '../model/understanding.dart';
import '../ports/platform.dart';
import '../services/contracts.dart';
import '../text/amounts.dart';
import '../text/dates.dart';

/// Pulls a basic understanding out of OCR text with keyword rules and
/// regular expressions, for when no vision model is used.
///
/// It is deliberately simple: a category from keyword counts, a summary from
/// a known company name or the most prominent line, amounts, dates and common
/// identifiers. See docs/architecture.md, section 7.4.
class RuleBasedExtractor implements OcrUnderstandingExtractor {
  const RuleBasedExtractor({this.defaultCurrency = 'INR'});

  final String defaultCurrency;

  /// Keywords per category, checked in this order. Ties go to the earlier one.
  static const categoryKeywords = <String, List<String>>{
    'utility_bill': [
      'bill',
      'electricity',
      'due date',
      'units',
      'consumer',
      'meter',
      'kwh',
    ],
    'receipt': ['receipt', 'subtotal', 'gst', 'qty', 'cashier'],
    'invoice': ['invoice', 'tax invoice', 'gstin'],
    'booking': ['booking', 'pnr', 'check-in', 'reservation', 'flight', 'seat'],
    'ticket': ['ticket', 'admit', 'show', 'screen', 'row'],
    'chat': ['typing', 'online', 'last seen', 'message'],
    'code': ['import', 'class', 'function', '=>', '{', 'def '],
    'map': ['directions', 'km', 'min drive', 'route'],
    'product': ['add to cart', 'buy now', 'in stock', 'rating'],
    'article': ['min read', 'published', 'author'],
  };

  /// Company names recognized in text, spelled the way they are stored.
  static const knownCompanies = [
    'Reliance',
    'Airtel',
    'Jio',
    'Amazon',
    'Flipkart',
    'Swiggy',
    'Zomato',
    'IndiGo',
    'Air India',
    'Uber',
    'Ola',
    'HDFC',
    'ICICI',
    'SBI',
    'Paytm',
    'PhonePe',
    'Google',
    'Apple',
    'Samsung',
    'Tata',
    'BESCOM',
    'Adani',
  ];

  static const _keywordStopwords = {
    'about',
    'also',
    'amount',
    'been',
    'date',
    'does',
    'each',
    'from',
    'have',
    'here',
    'into',
    'just',
    'like',
    'more',
    'name',
    'number',
    'only',
    'over',
    'page',
    'please',
    'some',
    'such',
    'than',
    'that',
    'their',
    'them',
    'then',
    'there',
    'they',
    'this',
    'time',
    'total',
    'under',
    'very',
    'were',
    'what',
    'when',
    'where',
    'which',
    'will',
    'with',
    'your',
  };

  static final Map<String, List<RegExp>> _categoryPatterns = {
    for (final entry in categoryKeywords.entries)
      entry.key: [for (final k in entry.value) _keywordPattern(k)],
  };

  static final _companyPatterns = [
    for (final name in knownCompanies)
      (
        name: name,
        pattern: RegExp(
          '(?<![a-z0-9])${RegExp.escape(name.toLowerCase()).replaceAll(' ', r'\s+')}(?![a-z0-9])',
          caseSensitive: false,
        ),
      ),
  ];

  static RegExp _keywordPattern(String keyword) {
    final escaped = RegExp.escape(keyword);
    final startsWord = RegExp(r'^[a-z0-9]').hasMatch(keyword);
    final endsWord = RegExp(r'[a-z0-9]$').hasMatch(keyword);
    return RegExp(
      '${startsWord ? '(?<![a-z0-9])' : ''}$escaped'
      '${endsWord ? '(?![a-z0-9])' : ''}',
    );
  }

  @override
  MemoryUnderstanding extract(OcrResult ocr, {required DateTime takenAt}) {
    final text = ocr.text;
    final lines = [
      for (final block in ocr.blocks)
        for (final line in block.lines)
          if (line.text.trim().isNotEmpty) line,
    ];
    final lower = text.toLowerCase();

    final (category, scored) = _category(lower, lines.length);
    final entities = _entities(text);
    final title = _titleLine(lines);
    final summary = _summary(category, entities, title);

    return MemoryUnderstanding(
      summary: summary,
      category: category,
      visualDescription: lines.length >= 5
          ? 'Text-heavy screen with ${lines.length} lines of text.'
          : 'Image with little or no text.',
      extractedText: text,
      keywords: _keywords(lower, category, entities),
      entities: entities,
      dates: _dates(lines, takenAt),
      amounts: _amounts(lines),
      attributes: _attributes(text),
      confidence: scored ? 0.35 : 0.15,
    );
  }

  (String, bool) _category(String lower, int lineCount) {
    var best = 'other';
    var bestScore = 0;
    for (final entry in _categoryPatterns.entries) {
      final score = entry.value.where((p) => p.hasMatch(lower)).length;
      if (score > bestScore) {
        best = entry.key;
        bestScore = score;
      }
    }
    if (bestScore >= 2) return (best, true);
    return (lineCount >= 8 ? 'document' : 'other', false);
  }

  List<EntityMention> _entities(String text) {
    final found = <({int at, String name})>[];
    for (final company in _companyPatterns) {
      final match = company.pattern.firstMatch(text);
      if (match != null) found.add((at: match.start, name: company.name));
    }
    found.sort((a, b) => a.at.compareTo(b.at));
    return [
      for (final f in found) EntityMention(type: 'company', value: f.name),
    ];
  }

  static final _statusBar = RegExp(r'^\d{1,2}:\d{2}|^[\d\s%.:]+$');
  static final _letter = RegExp('[a-zA-Z]');

  String? _titleLine(List<OcrLine> lines) {
    final candidates = [
      for (final line in lines)
        if (!_statusBar.hasMatch(line.text.trim())) line,
    ];
    if (candidates.isEmpty) return null;
    final imageBottom = lines.map((l) => l.bottom).reduce(math.max);
    OcrLine? tallest;
    for (final line in candidates) {
      if (line.top >= imageBottom / 3) continue;
      if (_letter.allMatches(line.text).length < 3) continue;
      if (tallest == null || line.height > tallest.height) tallest = line;
    }
    return (tallest ?? candidates.first).text.trim();
  }

  String _summary(
    String category,
    List<EntityMention> entities,
    String? title,
  ) {
    if (entities.isNotEmpty && category != 'other') {
      return '${entities.first.value} ${category.replaceAll('_', ' ')}';
    }
    if (title != null && title.isNotEmpty) {
      return title.length > 80 ? title.substring(0, 80).trimRight() : title;
    }
    return 'Image with no readable text';
  }

  static final _tokenPattern = RegExp('[a-z]{4,}');

  List<String> _keywords(
    String lower,
    String category,
    List<EntityMention> entities,
  ) {
    final keywords = <String>{
      if (category != 'other') ...category.split('_'),
      for (final e in entities) e.value.toLowerCase(),
    };
    final counts = <String, int>{};
    final prose = lower.replaceAll(_email, ' ').replaceAll(_url, ' ');
    for (final match in _tokenPattern.allMatches(prose)) {
      final token = match[0]!;
      if (_keywordStopwords.contains(token) || keywords.contains(token)) {
        continue;
      }
      counts[token] = (counts[token] ?? 0) + 1;
    }
    final order = counts.keys.toList();
    final ranked = [...order]
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : order.indexOf(a) - order.indexOf(b);
      });
    keywords.addAll(ranked.take(3));
    return keywords.toList();
  }

  static final _totalLabel = RegExp(
    r'(?<![a-z])(?:grand\s+)?total(?![a-z])|amount\s+due|payable',
    caseSensitive: false,
  );
  static final _dueLabel = RegExp(
    r'(?<![a-z])due(?![a-z])',
    caseSensitive: false,
  );
  static final _paidLabel = RegExp(
    r'paid\s+on|date\s+of\s+payment|payment\s+date|transaction\s+date',
    caseSensitive: false,
  );

  /// The line itself, or the line before it too when this line holds nothing
  /// but the value, as OCR often splits a label from its value.
  String _labelContext(List<OcrLine> lines, int index, String value) {
    final line = lines[index].text;
    final rest = line.replaceFirst(value, '');
    if (_letter.allMatches(rest).length >= 3 || index == 0) return line;
    return '${lines[index - 1].text} $line';
  }

  List<AmountMention> _amounts(List<OcrLine> lines) {
    final result = <AmountMention>[];
    for (var i = 0; i < lines.length; i++) {
      for (final amount in findAmounts(
        lines[i].text,
        defaultCurrency: defaultCurrency,
      )) {
        final context = _labelContext(lines, i, amount.raw);
        final mention = AmountMention(
          type: _totalLabel.hasMatch(context) ? 'total' : 'amount',
          value: amount.value,
          currency: amount.currency,
        );
        if (!result.contains(mention)) result.add(mention);
      }
    }
    return result;
  }

  List<DateMention> _dates(List<OcrLine> lines, DateTime takenAt) {
    final result = <DateMention>[];
    for (var i = 0; i < lines.length; i++) {
      for (final date in findDates(lines[i].text, reference: takenAt)) {
        final context = _labelContext(lines, i, date.raw);
        final type = _dueLabel.hasMatch(context)
            ? 'due_date'
            : _paidLabel.hasMatch(context)
            ? 'transaction_date'
            : 'date';
        final mention = DateMention(type: type, value: isoDate(date.date));
        if (!result.contains(mention)) result.add(mention);
      }
    }
    return result;
  }

  static final _identifierPatterns = <({String type, RegExp pattern})>[
    (
      type: 'booking_reference',
      pattern: RegExp(
        r'(?<![A-Za-z])[Pp][Nn][Rr](?:\s*(?:[Nn][Oo]\.?|[Nn]umber))?\s*[:#-]?\s*([A-Z0-9]{6})(?![A-Za-z0-9])',
      ),
    ),
    (
      type: 'order_number',
      pattern: RegExp(
        r'(?<![a-z])order\s*(?:id|no\.?|number|#)\s*[:#-]?\s*([a-z0-9-]{6,})',
        caseSensitive: false,
      ),
    ),
    (
      type: 'invoice_number',
      pattern: RegExp(
        r'(?<![a-z])invoice\s*(?:no\.?|number|#|id)\s*[:#-]?\s*([a-z0-9/-]{4,})',
        caseSensitive: false,
      ),
    ),
    (
      type: 'tracking_number',
      pattern: RegExp(
        r'(?<![a-z])(?:tracking|awb)\s*(?:id|no\.?|number|#)?\s*[:#-]?\s*([a-z0-9]{8,})',
        caseSensitive: false,
      ),
    ),
    (
      type: 'account_number',
      pattern: RegExp(
        r'(?<![a-z])(?:account|a/c|acct|consumer)\s*(?:no\.?|number|#|id)?\s*[:#-]?\s*([x*•\d][x*•\d -]{2,}\d)',
        caseSensitive: false,
      ),
    ),
  ];

  static final _email = RegExp(
    r'[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}',
  );
  static final _url = RegExp(
    r'''(?:https?://|www\.)[^\s<>"']+''',
    caseSensitive: false,
  );
  static final _phone = RegExp(
    r'(?<![\w+])(?:\+91|\+1)?[ -]?\d(?:[ -]?\d){9,12}(?![\w])',
  );
  static final _digit = RegExp(r'\d');

  List<AttributeMention> _attributes(String text) {
    final result = <AttributeMention>[];
    final taken = <(int, int)>[];

    void add(String type, String value, int start, int end) {
      taken.add((start, end));
      final mention = AttributeMention(type: type, value: value);
      if (!result.contains(mention)) result.add(mention);
    }

    for (final (:type, :pattern) in _identifierPatterns) {
      for (final match in pattern.allMatches(text)) {
        final value = match[1]!.trim();
        if (!_digit.hasMatch(value)) continue;
        if (type == 'account_number') {
          final digits = value.replaceAll(RegExp(r'\D'), '');
          if (digits.length < 4) continue;
          add(
            type,
            '•••• ${digits.substring(digits.length - 4)}',
            match.start,
            match.end,
          );
        } else {
          add(type, value, match.start, match.end);
        }
      }
    }

    for (final match in _phone.allMatches(text)) {
      final overlaps = taken.any((t) => match.start < t.$2 && t.$1 < match.end);
      if (overlaps) continue;
      final value = match[0]!.trim();
      final digits = _digit.allMatches(value).length;
      if (digits < 10 || digits > 13) continue;
      add('phone', value, match.start, match.end);
    }
    for (final match in _email.allMatches(text)) {
      add('email', match[0]!, match.start, match.end);
    }
    for (final match in _url.allMatches(text)) {
      final value = match[0]!.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), '');
      add('url', value, match.start, match.end);
    }
    return result;
  }
}
