import 'dart:math' as math;
import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';
import 'package:memora_providers/src/shared/image_payload.dart';
import 'package:memora_providers/src/shared/json_extract.dart';
import 'package:memora_providers/src/shared/json_read.dart';
import 'package:memora_providers/src/shared/replay_cache.dart';
import 'package:memora_providers/src/shared/schema.dart';
import 'package:memora_providers/src/shared/vectors.dart';
import 'package:test/test.dart';

import '../support/scripted_http.dart';

void main() {
  group('extractJsonObject', () {
    test('reads a bare object', () {
      expect(extractJsonObject('{"a": 1}'), {'a': 1});
    });

    test('reads a fenced block with a language tag', () {
      const text =
          'Here you go:\n```json\n{"summary": "Bill", "n": [1]}\n```\n';
      expect(extractJsonObject(text), {
        'summary': 'Bill',
        'n': [1],
      });
    });

    test('reads a fenced block without a language tag', () {
      expect(extractJsonObject('```\n{"ok": true}\n```'), {'ok': true});
    });

    test('finds an object inside prose, respecting braces in strings', () {
      const text =
          'Sure. {"text": "a } brace and a \\" quote", "b": {"c": 2}} Done.';
      expect(extractJsonObject(text), {
        'text': 'a } brace and a " quote',
        'b': {'c': 2},
      });
    });

    test('skips a broken object and finds a later one', () {
      expect(extractJsonObject('{oops} then {"x": 1}'), {'x': 1});
    });

    test('returns null when there is no object', () {
      expect(extractJsonObject('I cannot help with that.'), isNull);
      expect(extractJsonObject('[1, 2, 3]'), isNull);
      expect(extractJsonObject(''), isNull);
    });
  });

  group('ImagePayload', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);

    test('builds base64 and a data URI', () {
      final image = ImagePayload.of(png, 'image/png', providerId: 'openai');
      expect(image.base64Data, 'iVBORw0K');
      expect(image.dataUri, 'data:image/png;base64,iVBORw0K');
    });

    test('normalizes image/jpg', () {
      final image = ImagePayload.of(png, 'IMAGE/JPG', providerId: 'openai');
      expect(image.mimeType, 'image/jpeg');
    });

    test('rejects images over the limit as content problems', () {
      expect(
        () => ImagePayload.of(
          Uint8List(11),
          'image/png',
          providerId: 'openai',
          maxBytes: 10,
        ),
        throwsA(isA<AiContentException>()),
      );
      expect(defaultMaxImageBytes, 20 * 1024 * 1024);
    });

    test('rejects empty files, non-images and unsupported types', () {
      expect(
        () => ImagePayload.of(Uint8List(0), 'image/png', providerId: 'x'),
        throwsA(isA<AiContentException>()),
      );
      expect(
        () => ImagePayload.of(png, 'application/pdf', providerId: 'x'),
        throwsA(isA<AiContentException>()),
      );
      expect(
        () => ImagePayload.of(
          png,
          'image/heic',
          providerId: 'x',
          supportedMimeTypes: const {'image/png', 'image/jpeg'},
        ),
        throwsA(isA<AiContentException>()),
      );
    });
  });

  group('normalizedVector', () {
    test('L2-normalizes', () {
      final v = normalizedVector([3, 4]);
      expect(v, isA<Float32List>());
      expect(v[0], closeTo(0.6, 1e-6));
      expect(v[1], closeTo(0.8, 1e-6));
    });

    test('leaves a zero vector alone and rejects non-numbers', () {
      expect(normalizedVector([0, 0]), [0, 0]);
      expect(() => normalizedVector(['a']), throwsFormatException);
    });

    test('produces unit length for longer vectors', () {
      final v = normalizedVector([for (var i = 1; i <= 384; i++) i * 0.5]);
      var sum = 0.0;
      for (final x in v) {
        sum += x * x;
      }
      expect(math.sqrt(sum), closeTo(1, 1e-5));
    });
  });

  group('decodeArguments', () {
    test('accepts JSON text, maps and garbage', () {
      expect(decodeArguments('{"a": 1}'), {'a': 1});
      expect(decodeArguments({'b': 2}), {'b': 2});
      expect(decodeArguments('{not json'), isEmpty);
      expect(decodeArguments('[1]'), isEmpty);
      expect(decodeArguments(null), isEmpty);
      expect(decodeArguments(''), isEmpty);
    });
  });

  group('TurnReplayCache', () {
    const a = ToolCall(id: 'a', name: 't', arguments: {});
    const b = ToolCall(id: 'b', name: 't', arguments: {});
    const c = ToolCall(id: 'c', name: 't', arguments: {});

    const scope = 'openai|gpt-6-sol';

    test('finds data by the exact set of call ids', () {
      final cache = TurnReplayCache<String>();
      cache.remember(scope, [a, b], 'turn-1');
      expect(cache.lookup(scope, [b, a]), 'turn-1');
      expect(cache.lookup(scope, [a]), isNull);
      expect(cache.lookup(scope, [a, b, c]), isNull);
      expect(cache.lookup(scope, const []), isNull);
    });

    test('keeps providers and models apart', () {
      final cache = TurnReplayCache<String>();
      cache.remember(scope, [a], 'from openai');
      expect(cache.lookup('groq|qwen/qwen3.8-27b', [a]), isNull);
      expect(cache.lookup('openai|gpt-4.1-mini', [a]), isNull);
      expect(cache.lookup(scope, [a]), 'from openai');
    });

    test('forgets the oldest entries past capacity', () {
      final cache = TurnReplayCache<int>(capacity: 2);
      cache.remember(scope, [a], 1);
      cache.remember(scope, [b], 2);
      cache.remember(scope, [c], 3);
      expect(cache.lookup(scope, [a]), isNull);
      expect(cache.lookup(scope, [b]), 2);
      expect(cache.lookup(scope, [c]), 3);
    });
  });

  group('closedSchema', () {
    test('adds additionalProperties false to every object', () {
      expect(
        closedSchema(VisionPrompts.understandingSchema),
        fixtureJson('openai/understanding_schema_closed.json'),
      );
    });

    test('leaves the input untouched', () {
      final input = {
        'type': 'object',
        'properties': {
          'a': {'type': 'string'},
        },
      };
      closedSchema(input);
      expect(input.containsKey('additionalProperties'), isFalse);
    });
  });
}
