import 'package:memora_core/memora_core.dart';
import 'package:memora_database/memora_database.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  late MemoraDatabase db;
  late SearchStore search;
  late String billJul;
  late String billAug;
  late String billSep;
  late String macbook;
  late String flight;
  late String failed;
  final now = DateTime.utc(2026, 9, 15);

  Future<String> filed(
    DateTime takenAt,
    MemoryUnderstanding u,
    NormalizedFacts f,
  ) async {
    final id = await seedMemory(db, takenAt: takenAt);
    await db.memories.saveUnderstanding(id, u, f, now);
    setStatus(db, id, ProcessingStatus.ready);
    return id;
  }

  Future<String> bill(
    int month,
    double total,
    String display,
    String dueDate, {
    List<StoredEntity> extraEntities = const [],
  }) {
    const months = ['July', 'August', 'September'];
    return filed(
      DateTime.utc(2026, month, 5),
      understanding(
        summary: 'Reliance electricity bill for ${months[month - 7]} 2026',
        extractedText: 'Reliance Energy. Amount payable $display',
      ),
      facts(
        entities: [entity('company', 'Reliance'), ...extraEntities],
        attributes: [
          StoredAttribute(
            type: 'amount',
            value: display,
            valueNum: total,
            currency: 'INR',
            label: 'total',
          ),
          StoredAttribute(type: 'due_date', value: dueDate, valueDate: dueDate),
          textAttribute('account_number', '•••• 4471'),
        ],
        keywords: ['reliance', 'electricity', 'bill'],
      ),
    );
  }

  setUp(() async {
    db = openTestDatabase();
    search = db.search;

    billJul = await bill(7, 1690, '₹1,690', '2026-07-31');
    billAug = await bill(
      8,
      2103,
      '₹2,103',
      '2026-08-31',
      extraEntities: [entity('person', 'Asha Rao')],
    );
    billSep = await bill(
      9,
      1842,
      '₹1,842',
      '2026-09-30',
      extraEntities: [entity('person', 'ASHA RAO')],
    );
    macbook = await filed(
      DateTime.utc(2026, 8, 20),
      understanding(
        summary: 'MacBook Air M4 price comparison',
        category: 'comparison',
        visualDescription: 'A shopping page comparing two laptops.',
        extractedText: 'MacBook Air 13-inch M4 ₹1,24,900',
        keywords: const ['laptop'],
      ),
      facts(
        entities: [entity('product', 'MacBook Air'), entity('brand', 'Apple')],
        attributes: [
          const StoredAttribute(
            type: 'amount',
            value: '₹1,24,900',
            valueNum: 124900,
            currency: 'INR',
            label: 'price',
          ),
        ],
        keywords: ['laptop', 'macbook', 'comparison'],
      ),
    );
    flight = await filed(
      DateTime.utc(2026, 9, 10),
      understanding(
        summary: 'IndiGo flight to Goa',
        category: 'booking',
        visualDescription: 'A boarding pass in an airline app.',
        extractedText: 'IndiGo 6E 204 BLR to GOI. PNR K4T9RB. 18 Oct 2026',
        keywords: const ['flight'],
      ),
      facts(
        entities: [entity('company', 'IndiGo'), entity('location', 'Goa')],
        attributes: [
          textAttribute('seat', '14C'),
          dateAttribute('departure_date', '2026-10-18'),
          textAttribute('booking_reference', 'K4T9RB'),
        ],
        keywords: ['flight', 'booking', 'goa'],
      ),
    );
    failed = await seedMemory(db, takenAt: DateTime.utc(2026, 9, 12));
    setStatus(db, failed, ProcessingStatus.failed);
  });

  Future<List<String>> structured(RetrievalQuery query, {int limit = 500}) =>
      search.structured(query, limit: limit);

  group('structured', () {
    test('filters by category, newest taken first', () async {
      expect(
        await structured(const RetrievalQuery(categories: {'utility_bill'})),
        [billSep, billAug, billJul],
      );
      expect(
        await structured(
          const RetrievalQuery(categories: {'utility_bill', 'booking'}),
        ),
        [flight, billSep, billAug, billJul],
      );
    });

    test('returns everything newest first without filters', () async {
      expect(await structured(const RetrievalQuery()), [
        failed,
        flight,
        billSep,
        macbook,
        billAug,
        billJul,
      ]);
      expect(await structured(const RetrievalQuery(), limit: 2), [
        failed,
        flight,
      ]);
    });

    test('ignores text and strategies', () async {
      expect(
        await structured(
          const RetrievalQuery(
            text: 'flight',
            categories: {'utility_bill'},
            strategies: {RetrievalStrategy.semantic},
          ),
        ),
        [billSep, billAug, billJul],
      );
    });

    test('matches entity values whose accents were folded away', () async {
      // Entities are stored already folded, the way core normalizes them.
      final cafe = await filed(
        DateTime.utc(2026, 9, 2),
        understanding(summary: 'Cafe Coffee Day receipt', category: 'receipt'),
        facts(
          entities: [
            const StoredEntity(
              type: 'company',
              value: 'Café Coffee Day',
              normalizedValue: 'cafe coffee day',
            ),
          ],
        ),
      );

      expect(
        await structured(
          const RetrievalQuery(entities: [EntityFilter(value: 'Café')]),
        ),
        [cafe],
      );
      expect(
        await structured(
          const RetrievalQuery(entities: [EntityFilter(value: 'CAFÉ  COFFEE')]),
        ),
        [cafe],
      );
    });

    test('matches entities by normalized substring', () async {
      expect(
        await structured(
          const RetrievalQuery(entities: [EntityFilter(value: 'reliance')]),
        ),
        [billSep, billAug, billJul],
      );
      expect(
        await structured(
          const RetrievalQuery(entities: [EntityFilter(value: ' RELIAN ')]),
        ),
        [billSep, billAug, billJul],
      );
      expect(
        await structured(
          const RetrievalQuery(
            entities: [EntityFilter(value: 'reliance', type: 'company')],
          ),
        ),
        [billSep, billAug, billJul],
      );
      expect(
        await structured(
          const RetrievalQuery(
            entities: [EntityFilter(value: 'reliance', type: 'person')],
          ),
        ),
        isEmpty,
      );
    });

    test('requires every entity filter to match', () async {
      expect(
        await structured(
          const RetrievalQuery(
            entities: [
              EntityFilter(value: 'reliance'),
              EntityFilter(value: 'asha', type: 'person'),
            ],
          ),
        ),
        [billSep, billAug],
      );
    });

    test('treats LIKE wildcards in entity values literally', () async {
      expect(
        await structured(
          const RetrievalQuery(entities: [EntityFilter(value: '%')]),
        ),
        isEmpty,
      );
      expect(
        await structured(
          const RetrievalQuery(entities: [EntityFilter(value: 'r_liance')]),
        ),
        isEmpty,
      );
    });

    test('filters amounts by range and currency', () async {
      expect(
        await structured(
          const RetrievalQuery(
            attributes: [AttributeFilter(type: 'amount', min: 1800)],
          ),
        ),
        [billSep, macbook, billAug],
      );
      expect(
        await structured(
          const RetrievalQuery(
            attributes: [
              AttributeFilter(type: 'amount', min: 1800, currency: 'INR'),
            ],
          ),
        ),
        [billSep, macbook, billAug],
      );
      expect(
        await structured(
          const RetrievalQuery(
            attributes: [
              AttributeFilter(type: 'amount', min: 1800, currency: 'usd'),
            ],
          ),
        ),
        isEmpty,
      );
      expect(
        await structured(
          const RetrievalQuery(
            attributes: [
              AttributeFilter(
                type: 'amount',
                min: 1800,
                max: 2000,
                currency: 'INR',
              ),
            ],
          ),
        ),
        [billSep],
      );
      expect(
        await structured(
          const RetrievalQuery(
            attributes: [AttributeFilter(type: 'amount', max: 1690)],
          ),
        ),
        [billJul],
      );
    });

    test('filters date attributes by whole days', () async {
      expect(
        await structured(
          RetrievalQuery(
            attributes: [
              AttributeFilter(
                type: 'departure_date',
                dateRange: DateRange.month(2026, 10),
              ),
            ],
          ),
        ),
        [flight],
      );
      expect(
        await structured(
          RetrievalQuery(
            attributes: [
              AttributeFilter(
                type: 'departure_date',
                dateRange: DateRange.month(2026, 11),
              ),
            ],
          ),
        ),
        isEmpty,
      );
      expect(
        await structured(
          RetrievalQuery(
            attributes: [
              AttributeFilter(
                type: 'due_date',
                dateRange: DateRange(
                  start: DateTime(2026, 8, 31),
                  end: DateTime(2026, 9, 30),
                ),
              ),
            ],
          ),
        ),
        [billAug],
      );
      expect(
        await structured(
          RetrievalQuery(
            attributes: [
              AttributeFilter(
                type: 'due_date',
                dateRange: DateRange(start: DateTime(2026, 8, 31, 9)),
              ),
            ],
          ),
        ),
        [billSep],
      );
    });

    test('matches exact values ignoring case', () async {
      expect(
        await structured(
          const RetrievalQuery(
            attributes: [
              AttributeFilter(type: 'booking_reference', equals: 'k4t9rb'),
            ],
          ),
        ),
        [flight],
      );
      expect(
        await structured(
          const RetrievalQuery(
            attributes: [
              AttributeFilter(type: 'booking_reference', equals: 'K4T9R'),
            ],
          ),
        ),
        isEmpty,
      );
    });

    test('filters by taken date, status and ids', () async {
      expect(
        await structured(
          RetrievalQuery(takenBetween: DateRange.month(2026, 9)),
        ),
        [failed, flight, billSep],
      );
      expect(
        await structured(
          const RetrievalQuery(statuses: {ProcessingStatus.failed}),
        ),
        [failed],
      );
      expect(
        await structured(
          RetrievalQuery(
            categories: const {'utility_bill'},
            within: {billJul, flight},
          ),
        ),
        [billJul],
      );
      expect(await structured(const RetrievalQuery(within: {})), isEmpty);
    });

    test('never returns deleted memories', () async {
      setStatus(db, billJul, ProcessingStatus.deleted);
      expect(
        await structured(
          const RetrievalQuery(
            categories: {'utility_bill'},
            statuses: {ProcessingStatus.deleted, ProcessingStatus.ready},
          ),
        ),
        [billSep, billAug],
      );
    });
  });

  group('fullText', () {
    test('ranks matching memories with positive scores', () async {
      final hits = await search.fullText('electricity bill');
      expect(hits.map((h) => h.id).toSet(), {billJul, billAug, billSep});
      expect(hits.every((h) => h.score > 0), isTrue);
      for (var i = 1; i < hits.length; i++) {
        expect(hits[i - 1].score, greaterThanOrEqualTo(hits[i].score));
      }
    });

    test('puts stronger matches first', () async {
      final hits = await search.fullText('macbook laptop comparison');
      expect(hits.first.id, macbook);

      final goa = await search.fullText('goa flight');
      expect(goa.map((h) => h.id), [flight]);
    });

    test('matches prefixes, other cases and diacritics', () async {
      expect((await search.fullText('ELECTRIC')).length, 3);
      expect((await search.fullText('électricité')).length, 0);
      expect((await search.fullText('Électricity')).length, 3);
      expect((await search.fullText('k4t9')).single.id, flight);
    });

    test('respects within and limit', () async {
      final within = await search.fullText(
        'electricity',
        within: {billAug, flight},
      );
      expect(within.map((h) => h.id), [billAug]);
      expect(await search.fullText('bill', within: {}), isEmpty);
      expect(await search.fullText('bill', limit: 2), hasLength(2));
    });

    test('returns nothing for stopwords or empty text', () async {
      expect(await search.fullText('show me all the'), isEmpty);
      expect(await search.fullText(''), isEmpty);
    });

    test('treats FTS syntax as plain words', () async {
      final hits = await search.fullText('bill" OR 1=1 --');
      expect(hits.map((h) => h.id).toSet(), {billJul, billAug, billSep});
      expect(await search.fullText('NEAR('), isEmpty);
    });

    test('skips deleted memories', () async {
      setStatus(db, billJul, ProcessingStatus.deleted);
      final hits = await search.fullText('electricity');
      expect(hits.map((h) => h.id).toSet(), {billAug, billSep});
    });
  });

  group('cards', () {
    test('keep order and pick key facts', () async {
      await db.memories.setThumbnail(flight, 'thumbnails/flight.webp', now);
      final cards = await search.cards([
        flight,
        billAug,
        'missing',
        macbook,
        failed,
      ]);

      expect(cards.map((c) => c.id), [flight, billAug, macbook, failed]);

      final flightCard = cards[0];
      expect(flightCard.summary, 'IndiGo flight to Goa');
      expect(flightCard.category, 'booking');
      expect(flightCard.status, ProcessingStatus.ready);
      expect(flightCard.takenAt, DateTime.utc(2026, 9, 10));
      expect(flightCard.thumbnailPath, 'thumbnails/flight.webp');
      expect(flightCard.facts.keys, ['departure_date', 'booking_reference']);
      expect(flightCard.facts['departure_date'], '2026-10-18');
      expect(flightCard.facts['booking_reference'], 'K4T9RB');

      expect(cards[1].facts.keys, ['amount', 'due_date']);
      expect(cards[1].facts, {'amount': '₹2,103', 'due_date': '2026-08-31'});

      expect(cards[2].facts, {'amount': '₹1,24,900'});

      expect(cards[3].summary, isNull);
      expect(cards[3].status, ProcessingStatus.failed);
      expect(cards[3].facts, isEmpty);
    });

    test('use the first attribute of each kind', () async {
      final id = await filed(
        DateTime.utc(2026, 9, 1),
        understanding(summary: 'Order', category: 'receipt'),
        facts(
          attributes: [
            textAttribute('order_number', 'OD-1'),
            dateAttribute('transaction_date', '2026-09-01'),
            const StoredAttribute(
              type: 'amount',
              value: r'$12.99',
              valueNum: 12.99,
              currency: 'USD',
            ),
            const StoredAttribute(
              type: 'amount',
              value: r'$1.00',
              valueNum: 1,
              currency: 'USD',
            ),
            dateAttribute('delivery_date', '2026-09-04'),
            textAttribute('tracking_number', 'TRK-9'),
          ],
        ),
      );

      final card = (await search.cards([id])).single;
      expect(card.facts.keys, ['amount', 'transaction_date', 'order_number']);
      expect(card.facts.values, [r'$12.99', '2026-09-01', 'OD-1']);
    });

    test('are empty for no ids', () async {
      expect(await search.cards(const []), isEmpty);
    });
  });

  group('attributeValues', () {
    test('returns every matching attribute with the taken date', () async {
      final values = await search.attributeValues([
        billJul,
        flight,
        macbook,
        billAug,
      ], 'amount');

      expect(values.map((v) => v.memoryId), [billJul, macbook, billAug]);
      expect(values.map((v) => v.attribute.valueNum), [1690, 124900, 2103]);
      expect(values.first.attribute.currency, 'INR');
      expect(values.first.attribute.label, 'total');
      expect(values.first.attribute.value, '₹1,690');
      expect(values.first.takenAt, DateTime.utc(2026, 7, 5));
      expect(values.last.takenAt, DateTime.utc(2026, 8, 5));
    });

    test('returns one entry per attribute', () async {
      final id = await filed(
        DateTime.utc(2026, 9, 1),
        understanding(),
        facts(attributes: [amount(10), amount(20)]),
      );
      final values = await search.attributeValues([id], 'amount');
      expect(values.map((v) => v.attribute.valueNum), [10, 20]);
    });

    test('is empty for unknown types or no ids', () async {
      expect(await search.attributeValues([billJul], 'weight'), isEmpty);
      expect(await search.attributeValues(const [], 'amount'), isEmpty);
    });
  });

  group('sharingEntities', () {
    test('scores other memories by shared entity count', () async {
      final shared = await search.sharingEntities(billAug);
      expect(shared, [ScoredId(billSep, 2), ScoredId(billJul, 1)]);
    });

    test('respects the limit and skips deleted memories', () async {
      expect(await search.sharingEntities(billAug, limit: 1), [
        ScoredId(billSep, 2),
      ]);
      setStatus(db, billSep, ProcessingStatus.deleted);
      expect(await search.sharingEntities(billAug), [ScoredId(billJul, 1)]);
    });

    test('is empty when nothing is shared', () async {
      expect(await search.sharingEntities(macbook), isEmpty);
      expect(await search.sharingEntities(failed), isEmpty);
      expect(await search.sharingEntities('missing'), isEmpty);
    });
  });
}
