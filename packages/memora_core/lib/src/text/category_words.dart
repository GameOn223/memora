/// Everyday words that point at a category, shared by the query parser and
/// the on-device reranker so both read a question the same way.
library;

const categoryWordMap = <String, Set<String>>{
  'bill': {'utility_bill', 'invoice'},
  'bills': {'utility_bill', 'invoice'},
  'invoice': {'invoice'},
  'invoices': {'invoice'},
  'receipt': {'receipt'},
  'receipts': {'receipt'},
  'booking': {'booking', 'ticket'},
  'bookings': {'booking', 'ticket'},
  'ticket': {'booking', 'ticket'},
  'tickets': {'booking', 'ticket'},
  'flight': {'booking', 'ticket'},
  'flights': {'booking', 'ticket'},
  'place': {'place', 'map'},
  'places': {'place', 'map'},
  'map': {'place', 'map'},
  'maps': {'place', 'map'},
  'chat': {'chat'},
  'chats': {'chat'},
  'code': {'code'},
  'snippet': {'code'},
  'snippets': {'code'},
  'product': {'product', 'comparison'},
  'products': {'product', 'comparison'},
  'shopping': {'product', 'comparison'},
};

/// The categories [words] point at, if any.
Set<String> categoriesForWords(Iterable<String> words) => {
  for (final word in words) ...?categoryWordMap[word],
};
