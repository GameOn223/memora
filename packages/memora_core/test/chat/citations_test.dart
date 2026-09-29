import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

void main() {
  test('reads citation markers in order without repeats', () {
    expect(
      parseCitations(
        'The August bill was ₹2,103 [[m:aug]], more than July [[m:jul]] '
        'and September [[m:aug]].',
      ),
      ['aug', 'jul'],
    );
    expect(parseCitations('No sources here.'), isEmpty);
  });

  test('strips markers and tidies the spacing around them', () {
    expect(
      stripCitations('The August bill was ₹2,103 [[m:aug]].'),
      'The August bill was ₹2,103.',
    );
    expect(
      stripCitations('[[m:a]] Your bill [[m:b]] arrived [[m:c]]'),
      'Your bill arrived',
    );
    expect(
      stripCitations('Line one [[m:a]]\nLine two [[m:b]]'),
      'Line one\nLine two',
    );
  });

  test('leaves text with no markers alone', () {
    expect(stripCitations('Nothing to strip.'), 'Nothing to strip.');
  });
}
