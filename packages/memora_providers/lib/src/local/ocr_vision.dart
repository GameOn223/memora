import 'package:memora_core/memora_core.dart';

final _number = RegExp(r'\d(?:[\d,]*\d)?(?:\.\d+)?');
final _moneyLine = RegExp(
  r'[₹$€£¥]|\brs\.?|\binr\b|\busd\b|\beur\b|\bgbp\b|'
  r'\btotal\b|\bamount\b|\bpaid\b|\bdue\b|\bbalance\b|\bsubtotal\b',
  caseSensitive: false,
);
final _nonDigits = RegExp(r'\D');
final _zeros = RegExp(r'^0+$');

/// On-device vision: ML Kit text recognition followed by an
/// [OcrUnderstandingExtractor]. It reads the original file from disk, so
/// requests must carry an absolute image path.
class OcrVisionService implements VisionService {
  OcrVisionService(this._ocr, this._extractor);

  static const providerId = 'local';

  final OcrEngine _ocr;
  final OcrUnderstandingExtractor _extractor;

  @override
  Future<MemoryUnderstanding> analyze(VisionRequest request) async {
    final ocr = await _ocr.recognize(_path(request.absoluteImagePath));
    return _extractor.extract(ocr, takenAt: request.takenAt);
  }

  /// Confirms a value when its digits appear as a number in the OCR text.
  ///
  /// This can only ever confirm. There is no model here to read a different
  /// value, so [VerificationResult.observedValue] is always null and an
  /// unconfirmed answer means "could not tell", not "wrong". Two limits
  /// follow from that:
  ///
  /// - A value holding several numbers, such as the date `2026-08-31`, is
  ///   never confirmed, because its parts would match unrelated numbers.
  /// - A money field is confirmed only from a line that reads like money,
  ///   so an order number sharing those digits doesn't count as the total.
  @override
  Future<VerificationResult> verify(VerificationRequest request) async {
    final ocr = await _ocr.recognize(_path(request.absoluteImagePath));
    final expected = _expectedForms(request.expectedValue);
    if (expected.isEmpty) return const VerificationResult(confirmed: false);
    final text = _isMoney(request.attributeType)
        ? _moneyLines(ocr.text)
        : ocr.text;
    final seen = _numberForms(text);
    return VerificationResult(confirmed: expected.any(seen.contains));
  }

  /// Whether [attributeType] names a money value.
  static bool _isMoney(String attributeType) {
    const money = {
      'amount',
      'total',
      'subtotal',
      'price',
      'tax',
      'discount',
      'balance',
      'fee',
      'paid',
      'due',
    };
    final type = attributeType.toLowerCase();
    return money.contains(type) ||
        type.contains('amount') ||
        type.contains('price') ||
        type.contains('total');
  }

  /// Only the lines carrying a currency marker or an amount word.
  static String _moneyLines(String text) => [
    for (final line in text.split('\n'))
      if (_moneyLine.hasMatch(line)) line,
  ].join('\n');

  static String _path(String? path) {
    if (path == null || path.isEmpty) {
      throw const AiContentException(
        'On-device vision needs the image file on disk',
        providerId: providerId,
      );
    }
    return path;
  }

  /// A single number such as `₹2,103.00` keeps its number forms. Anything
  /// with several numbers, such as a date, must match all its digits at once.
  static Set<String> _expectedForms(String value) {
    final matches = _number.allMatches(value).toList();
    if (matches.length == 1) return _formsOf(matches.single[0]!);
    final digits = value.replaceAll(_nonDigits, '');
    return digits.isEmpty ? const {} : {digits};
  }

  static Set<String> _numberForms(String text) => {
    for (final match in _number.allMatches(text)) ..._formsOf(match[0]!),
  };

  /// `1,24,900` gives `124900`. `2,103.00` gives `210300` and `2103`.
  static Set<String> _formsOf(String number) {
    final plain = number.replaceAll(',', '');
    final dot = plain.indexOf('.');
    if (dot == -1) return {plain};
    final whole = plain.substring(0, dot);
    final fraction = plain.substring(dot + 1);
    return {'$whole$fraction', if (_zeros.hasMatch(fraction)) whole};
  }
}
