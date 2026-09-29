import 'package:memora_core/memora_core.dart';

import 'demo_images.dart';

/// One sample memory from the design, with everything vision would have
/// extracted from it.
class DemoMemorySpec {
  const DemoMemorySpec({
    required this.id,
    required this.daysAgo,
    required this.time,
    required this.status,
    required this.summary,
    required this.category,
    required this.kind,
    this.seed = 0,
    this.added,
    this.processed,
    this.description = '',
    this.entities = const [],
    this.attributes = const [],
    this.keywords = const [],
    this.failureReason,
    this.conversationCount,
    this.byteSize = 412 * 1024,
  });

  final String id;

  /// Calendar days before "now" the image was taken.
  final int daysAgo;

  /// Hour and minute the image was taken, as `HH:mm`.
  final String time;
  final ProcessingStatus status;
  final String summary;
  final String category;
  final DemoImageKind kind;
  final int seed;

  /// `(daysAgo, HH:mm)` when added. Defaults to the taken time.
  final (int, String)? added;

  /// `(daysAgo, HH:mm)` when processing finished, for ready memories.
  final (int, String)? processed;
  final String description;
  final List<StoredEntity> entities;
  final List<StoredAttribute> attributes;
  final List<String> keywords;
  final String? failureReason;

  /// Overrides the count of conversations citing this memory.
  final int? conversationCount;
  final int byteSize;
}

StoredAttribute _amount(
  double value,
  String display, {
  String label = 'total',
}) => StoredAttribute(
  type: 'amount',
  value: display,
  valueNum: value,
  currency: 'INR',
  label: label,
);

StoredAttribute _date(String type, String iso, String display) =>
    StoredAttribute(type: type, value: display, valueDate: iso);

StoredAttribute _attr(String type, String value) =>
    StoredAttribute(type: type, value: value);

StoredEntity _entity(String type, String value) => StoredEntity(
  type: type,
  value: value,
  normalizedValue: value.toLowerCase(),
);

const _reliance = StoredEntity(
  type: 'company',
  value: 'Reliance',
  normalizedValue: 'reliance',
);

List<String> _billKeywords(String month) => [
  'reliance',
  'electricity',
  'bill',
  'payment',
  month,
  'due date',
];

DemoMemorySpec _bill({
  required String id,
  required int daysAgo,
  required String time,
  required String month,
  required double amount,
  required String display,
  required String dueIso,
  required String dueDisplay,
  required int seed,
  (int, String)? added,
  (int, String)? processed,
  bool paid = true,
}) {
  return DemoMemorySpec(
    id: id,
    daysAgo: daysAgo,
    time: time,
    status: ProcessingStatus.ready,
    summary: 'Reliance electricity bill for $month 2026',
    category: 'utility_bill',
    kind: DemoImageKind.bill,
    seed: seed,
    added: added,
    processed: processed ?? (daysAgo, time),
    description:
        'A utility bill on a mobile screen from the Reliance Energy app.',
    entities: const [_reliance],
    attributes: [
      _amount(amount, display),
      _date('due_date', dueIso, dueDisplay),
      _attr('account_number', '•••• 4471'),
      if (paid) _attr('payment_status', 'paid'),
    ],
    keywords: _billKeywords(month.toLowerCase()),
  );
}

/// The twelve memories from the design plus five older Reliance bills that
/// the sample conversation cites.
final demoMemorySpecs = <DemoMemorySpec>[
  _bill(
    id: 'm1',
    daysAgo: 0,
    time: '09:42',
    month: 'September',
    amount: 1842,
    display: '₹1,842',
    dueIso: '2026-09-30',
    dueDisplay: '30 Sep 2026',
    seed: 0,
    added: (0, '09:43'),
    processed: (0, '09:43'),
    paid: false,
  ),
  const DemoMemorySpec(
    id: 'm2',
    daysAgo: 0,
    time: '08:15',
    status: ProcessingStatus.ready,
    summary: 'MacBook Air M4 vs ThinkPad X1 comparison',
    category: 'comparison',
    kind: DemoImageKind.comparison,
    processed: (0, '08:30'),
    description: 'A laptop comparison table on a shopping site.',
    entities: [
      StoredEntity(
        type: 'product',
        value: 'MacBook Air M4',
        normalizedValue: 'macbook air m4',
      ),
      StoredEntity(
        type: 'product',
        value: 'ThinkPad X1',
        normalizedValue: 'thinkpad x1',
      ),
    ],
    attributes: [
      StoredAttribute(
        type: 'amount',
        value: '₹1,24,900',
        valueNum: 124900,
        currency: 'INR',
        label: 'price',
      ),
      StoredAttribute(type: 'product_count', value: '3 products', valueNum: 3),
    ],
    keywords: ['laptop', 'macbook', 'thinkpad', 'comparison', 'price'],
  ),
  DemoMemorySpec(
    id: 'm3',
    daysAgo: 1,
    time: '19:04',
    status: ProcessingStatus.captured,
    summary: 'Coffee roastery on 12th Main, hours',
    category: 'place',
    kind: DemoImageKind.map,
    description: 'A map listing for a coffee roastery.',
    attributes: [_attr('hours', 'Closes 22:00')],
    keywords: const ['coffee', 'roastery', 'hours'],
  ),
  DemoMemorySpec(
    id: 'm4',
    daysAgo: 1,
    time: '14:22',
    status: ProcessingStatus.ready,
    summary: 'Flight BLR to GOA on 18 Oct, 6E 2134',
    category: 'booking',
    kind: DemoImageKind.booking,
    processed: (1, '14:40'),
    description: 'A flight booking confirmation in an airline app.',
    entities: [_entity('company', 'IndiGo'), _entity('location', 'Goa')],
    attributes: [
      _attr('booking_reference', 'PNR K4T9RB'),
      _attr('departure_time', '06:35'),
      _date('departure_date', '2026-10-18', '18 Oct 2026'),
    ],
    keywords: const ['flight', 'indigo', 'goa', 'booking', 'pnr'],
  ),
  DemoMemorySpec(
    id: 'm5',
    daysAgo: 1,
    time: '11:08',
    status: ProcessingStatus.captured,
    summary: 'Laptop shortlist from a price tracker',
    category: 'comparison',
    kind: DemoImageKind.receipt,
    seed: 1,
    attributes: [
      _amount(112400, '₹1,12,400', label: 'price'),
      _attr('row_count', '5 rows'),
    ],
    keywords: const ['laptop', 'price', 'shortlist'],
  ),
  _bill(
    id: 'm6',
    daysAgo: 3,
    time: '21:38',
    month: 'August',
    amount: 2103,
    display: '₹2,103',
    dueIso: '2026-08-31',
    dueDisplay: '31 Aug 2026',
    seed: 1,
    processed: (0, '09:45'),
  ),
  const DemoMemorySpec(
    id: 'm7',
    daysAgo: 3,
    time: '16:10',
    status: ProcessingStatus.failed,
    summary: 'Platform channel setup snippet for Flutter',
    category: 'reference',
    kind: DemoImageKind.code,
    failureReason: 'provider timeout',
    keywords: ['flutter', 'kotlin', 'method channel'],
  ),
  DemoMemorySpec(
    id: 'm8',
    daysAgo: 3,
    time: '13:02',
    status: ProcessingStatus.ready,
    summary: 'Vendor quote thread, two revisions',
    category: 'reference',
    kind: DemoImageKind.chat,
    processed: (0, '09:47'),
    description: 'A messaging thread with a vendor discussing a quote.',
    attributes: [
      _amount(48000, '₹48,000', label: 'quote'),
      _attr('revisions', '2 revisions'),
    ],
    keywords: const ['vendor', 'quote', 'revision'],
  ),
  DemoMemorySpec(
    id: 'm9',
    daysAgo: 18,
    time: '20:11',
    status: ProcessingStatus.ready,
    summary: 'Reliance electricity bill for July 2026',
    category: 'utility_bill',
    kind: DemoImageKind.bill,
    seed: 2,
    added: (0, '09:12'),
    processed: (0, '09:42'),
    description:
        'A utility bill on a mobile screen, taken in August and added to '
        'Memora a month later from the gallery.',
    entities: const [_reliance],
    attributes: [
      _amount(1690, '₹1,690'),
      _date('due_date', '2026-07-31', '31 Jul 2026'),
      _attr('account_number', '•••• 4471'),
    ],
    keywords: _billKeywords('july'),
    conversationCount: 3,
  ),
  DemoMemorySpec(
    id: 'm10',
    daysAgo: 18,
    time: '12:30',
    status: ProcessingStatus.captured,
    summary: 'Monitor price drop on a deal site',
    category: 'comparison',
    kind: DemoImageKind.shopping,
    added: (0, '09:12'),
    attributes: [
      _amount(24499, '₹24,499', label: 'price'),
      _attr('previous_price', 'was ₹31,000'),
    ],
    keywords: const ['monitor', 'deal', 'price drop'],
  ),
  DemoMemorySpec(
    id: 'm11',
    daysAgo: 18,
    time: '18:44',
    status: ProcessingStatus.captured,
    summary: 'Parking entrance for the east gate',
    category: 'place',
    kind: DemoImageKind.map,
    seed: 1,
    added: (0, '09:12'),
    attributes: [_attr('location_detail', 'Level 2 · gate B')],
    keywords: const ['parking', 'gate'],
  ),
  DemoMemorySpec(
    id: 'm12',
    daysAgo: 18,
    time: '09:05',
    status: ProcessingStatus.processing,
    summary: 'Grocery receipt, monthly run',
    category: 'receipt',
    kind: DemoImageKind.receipt,
    added: (0, '09:12'),
    attributes: [_amount(3218, '₹3,218'), _attr('item_count', '22 items')],
    keywords: const ['grocery', 'receipt'],
  ),
  _bill(
    id: 'b6',
    daysAgo: 78,
    time: '19:20',
    month: 'June',
    amount: 1455,
    display: '₹1,455',
    dueIso: '2026-06-30',
    dueDisplay: '30 Jun 2026',
    seed: 7,
  ),
  _bill(
    id: 'b5',
    daysAgo: 108,
    time: '08:48',
    month: 'May',
    amount: 1402,
    display: '₹1,402',
    dueIso: '2026-05-31',
    dueDisplay: '31 May 2026',
    seed: 6,
  ),
  _bill(
    id: 'b3',
    daysAgo: 170,
    time: '21:05',
    month: 'March',
    amount: 1614,
    display: '₹1,614',
    dueIso: '2026-03-31',
    dueDisplay: '31 Mar 2026',
    seed: 5,
  ),
  _bill(
    id: 'b2',
    daysAgo: 200,
    time: '18:30',
    month: 'February',
    amount: 2088,
    display: '₹2,088',
    dueIso: '2026-02-28',
    dueDisplay: '28 Feb 2026',
    seed: 4,
  ),
  _bill(
    id: 'b1',
    daysAgo: 228,
    time: '20:02',
    month: 'January',
    amount: 2014,
    display: '₹2,014',
    dueIso: '2026-01-31',
    dueDisplay: '31 Jan 2026',
    seed: 3,
  ),
];

/// A gallery image from the design's Add screen.
class DemoGallerySpec {
  const DemoGallerySpec(this.daysAgo, this.time, this.kind, this.seed);

  final int daysAgo;
  final String time;
  final DemoImageKind kind;
  final int seed;
}

const demoGallerySpecs = <DemoGallerySpec>[
  DemoGallerySpec(0, '09:40', DemoImageKind.bill, 0),
  DemoGallerySpec(0, '09:02', DemoImageKind.chat, 1),
  DemoGallerySpec(0, '08:14', DemoImageKind.shopping, 1),
  DemoGallerySpec(1, '19:01', DemoImageKind.map, 0),
  DemoGallerySpec(1, '17:26', DemoImageKind.receipt, 0),
  DemoGallerySpec(1, '15:40', DemoImageKind.code, 1),
  DemoGallerySpec(1, '14:20', DemoImageKind.booking, 1),
  DemoGallerySpec(1, '12:12', DemoImageKind.chat, 2),
  DemoGallerySpec(1, '11:05', DemoImageKind.shopping, 0),
  DemoGallerySpec(3, '21:30', DemoImageKind.bill, 1),
  DemoGallerySpec(3, '18:02', DemoImageKind.map, 1),
  DemoGallerySpec(3, '10:44', DemoImageKind.receipt, 1),
];

/// Gallery images preselected in the design's Add screen: g1, g2, g4, g5,
/// g7, g10 and g11.
const demoPreselectedGallery = [0, 1, 3, 4, 6, 9, 10];
