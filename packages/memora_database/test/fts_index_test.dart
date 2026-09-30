import 'package:memora_database/memora_database.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The FTS5 tokenizer settings decide what a word is, and changing them later
/// means rebuilding the index for everyone. These tests pin the two things
/// the choice has to get right.
void main() {
  late MemoraDatabase db;
  final now = DateTime.utc(2026, 9, 15);

  setUp(() => db = openTestDatabase());

  Future<String> filed(String summary, String extractedText) async {
    final id = await seedMemory(db);
    await db.memories.saveUnderstanding(
      id,
      understanding(
        summary: summary,
        extractedText: extractedText,
        keywords: const [],
      ),
      facts(),
      now,
    );
    return id;
  }

  Set<String> indexedTerms() {
    db.connection.execute(
      "CREATE VIRTUAL TABLE probe_vocab USING fts5vocab(memories_fts, 'row')",
    );
    final terms = db.connection
        .select('SELECT term FROM probe_vocab')
        .map((row) => row['term'] as String)
        .toSet();
    db.connection.execute('DROP TABLE probe_vocab');
    return terms;
  }

  test('keeps Devanagari words whole', () async {
    final id = await filed('बिजली बिल अगस्त 2026', 'कुल राशि ₹1,842');

    expect(
      indexedTerms(),
      containsAll(<String>['बिजली', 'बिल', 'अगस्त', 'राशि']),
      reason: 'vowel signs belong to the word they sit on',
    );
    expect((await db.search.fullText('बिजली')).single.id, id);
    expect((await db.search.fullText('अगस्त')).single.id, id);
    expect(await db.search.fullText('राख'), isEmpty);
  });

  test('still folds accents off Latin words', () async {
    final id = await filed('Café Zürich receipt', 'Rechnung für Kaffee');

    expect(indexedTerms(), containsAll(<String>['cafe', 'zurich', 'fur']));
    expect((await db.search.fullText('cafe')).single.id, id);
    expect((await db.search.fullText('Café')).single.id, id);
    expect((await db.search.fullText('ZURICH')).single.id, id);
  });
}
