import 'package:memora_providers/memora_providers.dart';
import 'package:test/test.dart';

/// Everything the filter hands over for [chunks], joined.
String cleaned(List<String> chunks, {int maxChars = 1 << 20}) {
  final filter = LocalReplyFilter(maxChars: maxChars);
  final out = StringBuffer();
  for (final chunk in chunks) {
    out.write(filter.add(chunk));
    if (filter.done) return out.toString();
  }
  out.write(filter.finish());
  return out.toString();
}

void main() {
  group('LocalReplyFilter', () {
    test('plain text comes through as it arrives', () {
      final filter = LocalReplyFilter();
      final pieces = [
        for (final chunk in ['Your ', 'August bill ', 'was 2,103.'])
          filter.add(chunk),
      ];
      pieces.add(filter.finish());

      expect(pieces.join(), 'Your August bill was 2,103.');
      expect(
        pieces.where((p) => p.isNotEmpty),
        isNotEmpty,
        reason: 'text has to be handed over as it comes, not all at the end',
      );
    });

    test('the end marker ends the reply', () {
      expect(cleaned(['Done.<end_of_turn>and more']), 'Done.');
    });

    test('an end marker split across chunks is still caught', () {
      // The thing this class exists for. The old code only ever saw whole
      // replies, so a marker never arrived in halves.
      expect(cleaned(['Done.<end_of', '_turn>and more']), 'Done.');
      expect(cleaned(['Done.<', 'end_of_turn>x']), 'Done.');
      expect(cleaned(['Done.<end_of_tur', 'n>x']), 'Done.');
      for (var at = 1; at < '<end_of_turn>'.length; at++) {
        final marker = '<end_of_turn>';
        expect(
          cleaned([
            'Hi.${marker.substring(0, at)}',
            '${marker.substring(at)}x',
          ]),
          'Hi.',
          reason: 'split at $at',
        );
      }
    });

    test('markers to drop are removed wherever they land', () {
      // startModel is the whole header, marker and role together, so the
      // newline left behind is trimmed as leading space.
      expect(cleaned(['<start_of_turn>model\nHello', ' there']), 'Hello there');
      expect(cleaned(['A<start_of', '_turn>B']), 'AB');
    });

    test('nothing is held back once the stream ends', () {
      // The tail is only held in case it becomes a marker. When the stream
      // ends it is just text.
      expect(cleaned(['Yes']), 'Yes');
      expect(cleaned(['<']), '<');
      expect(cleaned(['a<b']), 'a<b');
    });

    test('the ends are trimmed but the middle is left alone', () {
      expect(cleaned(['  Hello  ', ' world  ']), 'Hello   world');
    });

    test('maxChars stops a model that will not stop', () {
      expect(cleaned(['abcdefghij'], maxChars: 4), 'abcd');
      final filter = LocalReplyFilter(maxChars: 4);
      // Ordinary text, so none of it is held back and the limit bites at
      // once rather than waiting for the stream to end.
      expect(filter.add('abcdefghij'), 'abcd');
      expect(filter.done, isTrue);
    });

    test('text arriving one character at a time still comes out whole', () {
      const reply = 'The highest was August at 2,103.<end_of_turn>';
      expect(
        cleaned([for (final char in reply.split('')) char]),
        'The highest was August at 2,103.',
      );
    });

    test('nothing after done', () {
      final filter = LocalReplyFilter();
      filter.add('Hi.<end_of_turn>');
      expect(filter.add('more'), isEmpty);
      expect(filter.finish(), isEmpty);
    });

    test('an empty reply is empty, not whitespace', () {
      expect(cleaned(['   ']), '');
      expect(cleaned([]), '');
    });
  });
}
