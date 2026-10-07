import '../text/normalize.dart';

/// Whether a question is asking about the memories someone saved, or is a
/// general one any assistant could answer.
///
/// A capable model decides this itself, from the instructions in
/// [SystemPrompt]. This exists for the small on-device models, which often
/// answer in plain prose when they should have called a tool. That silence
/// cannot be told apart from a deliberate direct answer, so the question is
/// read instead: for anything that might be about their own things, a plain
/// answer is treated as a failure to search and the deterministic path takes
/// over. For a plainly general question, a plain answer is the answer.
///
/// Deliberately generous about what counts as personal. A search that finds
/// nothing is a cheap, honest answer. A confident invention about someone's
/// electricity bill is neither, and they have no way of telling.
abstract final class QuestionKind {
  /// First-person references. Someone asking about "my" anything is asking
  /// about their own things.
  static const _personalWords = {
    'my',
    'mine',
    'i',
    'ive',
    'id',
    'im',
    'me',
    'our',
    'ours',
    'we',
    'us',
  };

  /// Words that belong to what Memora holds. A question using one is about
  /// saved images far more often than not.
  static const _memoryWords = {
    'memory',
    'memories',
    'saved',
    'save',
    'screenshot',
    'screenshots',
    'image',
    'images',
    'photo',
    'photos',
    'picture',
    'pictures',
    'bill',
    'bills',
    'invoice',
    'invoices',
    'receipt',
    'receipts',
    'ticket',
    'tickets',
    'booking',
    'bookings',
    'reservation',
    'order',
    'orders',
    'payment',
    'payments',
    'due',
    'paid',
    'amount',
    'total',
    'price',
    'cost',
    'spent',
    'spend',
    'product',
    'products',
    'document',
    'documents',
    'reference',
    'account',
    'card',
    'place',
    'places',
    'trip',
    'flight',
    'hotel',
    'address',
    'map',
    'code',
    'password',
    'otp',
  };

  /// Words that ask about the collection itself, such as "how many do I
  /// have", which is a search even without anything else personal in it.
  static const _collectionWords = {
    'everything',
    'anything',
    'all',
    'how',
    'many',
    'much',
    'show',
    'find',
    'list',
    'search',
    'when',
    'where',
    'which',
  };

  /// Words, folded, with nothing dropped.
  ///
  /// Not [searchTokens]: that exists for matching against saved text, so it
  /// removes stopwords and single characters, and `i`, `my`, `show`, `when`
  /// and `all` are exactly the words that decide this.
  static final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

  static Set<String> words(String question) => {
    for (final match in _word.allMatches(foldForMatch(question))) match[0]!,
  };

  /// Whether [question] should be searched rather than answered directly.
  ///
  /// True unless the question is plainly general. All the context this has
  /// is the question itself, so it errs toward true.
  static bool needsMemories(String question) {
    final words = QuestionKind.words(question);
    if (words.isEmpty) return false;
    if (words.any(_personalWords.contains)) return true;
    if (words.any(_memoryWords.contains)) return true;
    // A bare "how many" or "show me" with nothing else to go on is still
    // about the collection, because there is nothing else here to ask about.
    return words.length <= 4 && words.any(_collectionWords.contains);
  }

  /// Whether a plain-prose reply to [question] can be taken at face value,
  /// given that tools were offered and none was called.
  static bool directAnswerIsFine(String question) => !needsMemories(question);
}
