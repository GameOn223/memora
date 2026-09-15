import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

/// Builds an OCR result with one block per line. Each entry is the text, the
/// top edge and the line height in pixels.
OcrResult _ocr(List<(String, int, int)> lines) => OcrResult(
  blocks: [
    for (final (text, top, height) in lines)
      OcrBlock(
        lines: [
          OcrLine(
            text: text,
            left: 40,
            top: top,
            right: 1040,
            bottom: top + height,
          ),
        ],
      ),
  ],
);

final _takenAt = DateTime(2026, 8, 20);

void main() {
  const extractor = RuleBasedExtractor();

  group('electricity bill', () {
    final ocr = _ocr([
      ('9:41', 10, 20),
      ('Reliance Energy', 120, 60),
      ('Electricity Bill', 200, 36),
      ('Consumer No: 150012345678', 300, 24),
      ('Bill Date: 01/08/2026', 900, 24),
      ('Due Date: 31/08/2026', 940, 24),
      ('Units consumed: 342 kWh', 980, 24),
      ('Amount Payable', 1020, 24),
      ('₹1,842.00', 1050, 30),
      ('Customer care: +91 98450 12345', 1100, 24),
      ('Email: care@reliance.example.com', 1140, 24),
      ('Pay at https://pay.example.com/bill.', 1180, 24),
    ]);
    final u = extractor.extract(ocr, takenAt: _takenAt);

    test('keeps the OCR text', () {
      expect(u.extractedText, ocr.text);
    });

    test('picks the category and summary', () {
      expect(u.category, 'utility_bill');
      expect(u.summary, 'Reliance utility bill');
      expect(u.confidence, 0.35);
    });

    test('finds the company', () {
      expect(u.entities, [
        const EntityMention(type: 'company', value: 'Reliance'),
      ]);
    });

    test('labels the payable amount as the total', () {
      expect(u.amounts, [
        const AmountMention(type: 'total', value: 1842, currency: 'INR'),
      ]);
    });

    test('types due and other dates', () {
      expect(u.dates, [
        const DateMention(type: 'date', value: '2026-08-01'),
        const DateMention(type: 'due_date', value: '2026-08-31'),
      ]);
    });

    test('pulls identifiers and masks account numbers', () {
      expect(
        u.attributes,
        containsAll(const [
          AttributeMention(type: 'account_number', value: '•••• 5678'),
          AttributeMention(type: 'phone', value: '+91 98450 12345'),
          AttributeMention(type: 'email', value: 'care@reliance.example.com'),
          AttributeMention(type: 'url', value: 'https://pay.example.com/bill'),
        ]),
      );
      expect(
        u.attributes.where((a) => a.type == 'phone'),
        hasLength(1),
        reason: 'the consumer number is not a phone number',
      );
    });

    test('keywords include category words, the company and frequent words', () {
      expect(
        u.keywords,
        containsAll(['utility', 'bill', 'reliance', 'electricity']),
      );
      expect(u.keywords.toSet(), hasLength(u.keywords.length));
    });

    test('describes a text-heavy screen', () {
      expect(u.visualDescription, 'Text-heavy screen with 12 lines of text.');
    });
  });

  group('flight booking', () {
    final u = extractor.extract(
      _ocr([
        ('10:05', 8, 20),
        ('IndiGo', 90, 64),
        ('Booking confirmed', 170, 30),
        ('PNR: K4T9RB', 240, 28),
        ('Flight 6E 2134  BLR to GOI', 600, 28),
        ('Departure 18 Oct 2026 06:15', 640, 28),
        ('Seat 14C', 680, 28),
        ('Total fare ₹5,400', 720, 28),
        ('Order ID: 402-7788123', 760, 28),
      ]),
      takenAt: _takenAt,
    );

    test('is a booking with a reference', () {
      expect(u.category, 'booking');
      expect(u.summary, 'IndiGo booking');
      expect(u.entities.single.value, 'IndiGo');
      expect(
        u.attributes,
        containsAll(const [
          AttributeMention(type: 'booking_reference', value: 'K4T9RB'),
          AttributeMention(type: 'order_number', value: '402-7788123'),
        ]),
      );
      expect(u.amounts.single.type, 'total');
      expect(u.amounts.single.value, 5400);
      expect(u.dates.single.value, '2026-10-18');
    });
  });

  group('chat screenshot', () {
    final u = extractor.extract(
      _ocr([
        ('9:41', 10, 20),
        ('Rahul', 80, 40),
        ('online', 125, 18),
        ('Are we still on for dinner tonight?', 700, 30),
        ('Yes, 8 pm at the usual place', 760, 30),
        ('typing...', 1900, 20),
        ('Message', 2300, 30),
      ]),
      takenAt: _takenAt,
    );

    test('is a chat summarized by its title line', () {
      expect(u.category, 'chat');
      expect(u.summary, 'Rahul');
      expect(u.entities, isEmpty);
      expect(u.amounts, isEmpty);
    });
  });

  group('code screenshot', () {
    final u = extractor.extract(
      _ocr([
        ('main.dart', 40, 30),
        ("import 'package:flutter/material.dart';", 120, 30),
        ('class MemoraApp extends StatelessWidget {', 160, 30),
        (
          '  Widget build(BuildContext context) => const Placeholder();',
          200,
          30,
        ),
        ('}', 240, 30),
      ]),
      takenAt: _takenAt,
    );

    test('is code', () {
      expect(u.category, 'code');
      expect(u.summary, 'main.dart');
      expect(u.confidence, 0.35);
    });
  });

  group('empty image', () {
    final u = extractor.extract(const OcrResult(blocks: []), takenAt: _takenAt);

    test('says there is no readable text', () {
      expect(u.summary, 'Image with no readable text');
      expect(u.category, 'other');
      expect(u.visualDescription, 'Image with little or no text.');
      expect(u.extractedText, '');
      expect(u.keywords, isEmpty);
      expect(u.confidence, 0.15);
    });
  });

  test('many lines with no category keywords is a document', () {
    final u = extractor.extract(
      _ocr([
        for (var i = 0; i < 9; i++) ('Paragraph number $i here', i * 40, 24),
      ]),
      takenAt: _takenAt,
    );
    expect(u.category, 'document');
    expect(u.confidence, 0.15);
  });

  test('long title lines are truncated to 80 characters', () {
    final title = '${'A' * 30} ${'b' * 70}';
    final u = extractor.extract(
      _ocr([(title, 10, 40), ('short', 200, 20)]),
      takenAt: _takenAt,
    );
    expect(u.summary.length, 80);
  });
}
