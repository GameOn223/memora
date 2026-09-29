import 'package:intl/intl.dart';
import 'package:memora_core/memora_core.dart';

import '../../widgets/memory_labels.dart';

/// One row of the extracted table.
typedef FactRow = (String label, String value);

const _labels = {
  'account_number': 'Account',
  'booking_reference': 'Booking',
  'invoice_number': 'Invoice',
  'order_number': 'Order',
  'tracking_number': 'Tracking',
  'product_count': 'Products',
  'item_count': 'Items',
  'row_count': 'Rows',
  'payment_status': 'Status',
  'previous_price': 'Before',
  'location_detail': 'Where',
  'url': 'Link',
};

String factLabel(String type) => _labels[type] ?? sentenceCase(type);

/// Facts in the order the design lists them: the amount, who it involves,
/// the dates, then identifiers, then when the image arrived.
List<FactRow> factRows(MemoryDetails details) {
  final attributes = details.attributes;
  final rows = <FactRow>[
    for (final a in attributes)
      if (a.type == 'amount') (factLabel(a.type), a.value),
    for (final e in details.entities) (sentenceCase(e.type), e.value),
    for (final a in attributes)
      if (a.type != 'amount' && a.valueDate != null)
        (factLabel(a.type), a.value),
    for (final a in attributes)
      if (a.type != 'amount' && a.valueDate == null)
        (factLabel(a.type), a.value),
  ];
  final taken = DateFormat('d MMM y, HH:mm').format(details.memory.takenAt);
  final added = DateFormat('d MMM y, HH:mm').format(details.memory.addedAt);
  return [...rows, ('Image taken', taken), ('Added to Memora', added)];
}

/// `1080 × 2400 · png · 412 KB`
String imageMeta(Memory memory) {
  final type = memory.mimeType.split('/').last;
  return '${memory.width} × ${memory.height} · $type · '
      '${byteSize(memory.byteSize)}';
}

/// The provenance lines at the bottom of the detail screen.
List<String> provenanceLines(MemoryDetails details) {
  final lines = <String>[];
  ProcessingRecord? latest(Capability capability) {
    for (final record in details.processing) {
      if (record.capability == capability &&
          record.outcome == ProcessingOutcome.succeeded) {
        return record;
      }
    }
    return null;
  }

  final vision = latest(Capability.vision);
  if (vision != null) {
    lines.add('Vision · ${vision.provider} / ${vision.model}');
  }
  final embedding = latest(Capability.embeddings);
  if (embedding != null) {
    lines.add('Embedding · ${embedding.provider} / ${embedding.model}');
  }
  final format = DateFormat('d MMM HH:mm');
  final queued = 'Queued ${format.format(details.memory.addedAt)}';
  final processed = details.memory.processedAt;
  lines.add(
    processed == null
        ? queued
        : '$queued · processed ${format.format(processed)}',
  );
  return lines;
}

/// The note shown when an image was added on a later day than it was taken.
String filedUnderNote(Memory memory) {
  final taken = DateFormat('d MMMM y').format(memory.takenAt);
  final when = memory.processedAt ?? memory.addedAt;
  final day = DateFormat('d MMMM').format(when);
  final verb = memory.processedAt == null ? 'Adding it on' : 'Processing on';
  return 'Filed under $taken, the date the image was taken. $verb $day does '
      'not move it.';
}
