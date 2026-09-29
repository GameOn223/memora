import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:memora_core/memora_core.dart';
import 'package:memora_providers/memora_providers.dart';
import 'package:test/test.dart';

import '../support/scripted_http.dart';

void main() {
  late ScriptedHttp http_;
  late JsonClient client;
  final url = Uri.parse('https://api.example.com/v1/chat/completions');

  setUp(() {
    http_ = ScriptedHttp();
    client = JsonClient(http_.client);
  });

  Future<Map<String, Object?>> post({Map<String, String> headers = const {}}) =>
      client.post(url, {'a': 1}, headers: headers, providerId: 'groq');

  Matcher throwsAi<T extends AiException>({String? message, Object? contains}) {
    var matcher = isA<T>().having((e) => e.providerId, 'providerId', 'groq');
    if (message != null) {
      matcher = matcher.having((e) => e.message, 'message', message);
    }
    if (contains != null) {
      matcher = matcher.having((e) => e.message, 'message', contains);
    }
    return throwsA(matcher);
  }

  group('success', () {
    test('posts JSON with headers and decodes the object', () async {
      http_.reply({'ok': true, 'text': 'Café ₹1,842'});

      final result = await post(headers: {'authorization': 'Bearer secret'});

      expect(result, {'ok': true, 'text': 'Café ₹1,842'});
      final request = http_.requests.single;
      expect(request.method, 'POST');
      expect(request.url, url);
      expect(request.headers['content-type'], startsWith('application/json'));
      expect(request.headers['authorization'], 'Bearer secret');
      expect(http_.body(0), {'a': 1});
    });

    test('get sends no body', () async {
      http_.reply({
        'data': [
          {'id': 'x'},
        ],
      });
      final result = await client.get(
        Uri.parse('https://api.example.com/v1/models'),
        providerId: 'groq',
      );
      expect(result['data'], isA<List<Object?>>());
      expect(http_.requests.single.method, 'GET');
    });

    test('decodes UTF-8 even without a charset', () async {
      http_.respondWith(
        (_) async => http.Response.bytes(utf8.encode('{"v":"₹ é"}'), 200),
      );
      expect(await post(), {'v': '₹ é'});
    });

    test('a body that is not JSON is transient', () async {
      http_.replyRaw('<html>Bad gateway</html>');
      await expectLater(post(), throwsAi<AiTransientException>());
    });

    test('a JSON array body is transient', () async {
      http_.replyRaw('[1, 2]');
      await expectLater(post(), throwsAi<AiTransientException>());
    });
  });

  group('status mapping', () {
    test('400 about the image is a content problem', () async {
      http_.reply({
        'error': {'message': 'Invalid image: the image could not be decoded'},
      }, status: 400);
      await expectLater(
        post(),
        throwsAi<AiContentException>(
          contains: contains('could not be decoded'),
        ),
      );
    });

    test('400 about safety is a content problem', () async {
      http_.reply({
        'error': {'message': 'Request blocked by safety system'},
      }, status: 400);
      await expectLater(post(), throwsAi<AiContentException>());
    });

    test('other 400 is a configuration problem with the message', () async {
      http_.reply({
        'error': {
          'message': 'Unrecognized request argument supplied: foo',
          'type': 'invalid_request_error',
        },
      }, status: 400);
      await expectLater(
        post(),
        throwsAi<AiConfigurationException>(
          contains: contains('Unrecognized request argument supplied: foo'),
        ),
      );
    });

    test('401 and 403 say the key was rejected', () async {
      http_.reply({
        'error': {'message': 'Incorrect API key provided: gsk_abcd****wxyz'},
      }, status: 401);
      await expectLater(
        post(),
        throwsAi<AiConfigurationException>(message: 'The API key was rejected'),
      );

      http_.reply({
        'error': {'message': 'Forbidden'},
      }, status: 403);
      await expectLater(
        post(),
        throwsAi<AiConfigurationException>(
          contains: startsWith('The API key was rejected'),
        ),
      );
    });

    test('404 says the model or endpoint was not found', () async {
      http_.reply({
        'error': {'message': 'The model `llama-9` does not exist'},
      }, status: 404);
      await expectLater(
        post(),
        throwsAi<AiConfigurationException>(
          contains: allOf(
            startsWith('Model or endpoint not found'),
            contains('llama-9'),
          ),
        ),
      );
    });

    for (final status in [408, 409, 425, 429, 500, 502, 503, 529]) {
      test('$status is transient', () async {
        http_.reply({'error': 'busy'}, status: status);
        await expectLater(post(), throwsAi<AiTransientException>());
      });
    }

    test('Retry-After in seconds is carried', () async {
      http_.reply(
        {
          'error': {'message': 'Rate limit reached'},
        },
        status: 429,
        headers: {'retry-after': '17'},
      );
      await expectLater(
        post(),
        throwsA(
          isA<AiTransientException>()
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 17),
              )
              .having((e) => e.message, 'message', contains('Rate limit')),
        ),
      );
    });

    test('provider messages are trimmed to 200 characters', () async {
      http_.reply({
        'error': {'message': 'x' * 500},
      }, status: 400);
      try {
        await post();
        fail('expected an exception');
      } on AiConfigurationException catch (e) {
        final detail = e.message.substring(e.message.indexOf('x'));
        expect(detail.length, lessThanOrEqualTo(200));
      }
    });

    test('reads Gemini, Anthropic and NVIDIA error shapes', () {
      expect(
        providerErrorMessage(
          '{"error":{"code":400,"message":"API key not valid.","status":"INVALID_ARGUMENT"}}',
        ),
        'API key not valid.',
      );
      expect(
        providerErrorMessage(
          '{"type":"error","error":{"type":"not_found_error","message":"model: x"}}',
        ),
        'model: x',
      );
      expect(
        providerErrorMessage('{"title":"Bad Request","detail":"Bad passage"}'),
        'Bad passage',
      );
      expect(
        providerErrorMessage('{"error":"model not found"}'),
        'model not found',
      );
      expect(
        providerErrorMessage('[{"error":{"message":"wrapped in a list"}}]'),
        'wrapped in a list',
      );
      expect(providerErrorMessage('not json'), isNull);
    });

    test('never repeats the API key sent in headers', () async {
      const key = 'nvapi-SECRET1234567890abcdef';
      http_.reply({
        'error': {'message': 'Bad request for key $key and model x'},
      }, status: 400);
      try {
        await post(headers: {'authorization': 'Bearer $key'});
        fail('expected an exception');
      } on AiException catch (e) {
        expect(e.message, isNot(contains(key)));
        expect(e.toString(), isNot(contains('SECRET')));
      }
    });

    test('redacts key-shaped strings even without a header', () {
      expect(
        redactSecrets('bad key sk-ant-api03-abcdefghijklmnop here', const []),
        isNot(contains('abcdefghijklmnop')),
      );
      expect(
        redactSecrets('key AIzaSyA1234567890abcdefghijklmnop', const []),
        isNot(contains('AIzaSy')),
      );
    });
  });

  group('transport failures', () {
    test('timeout is transient', () async {
      client = JsonClient(
        http_.client,
        timeout: const Duration(milliseconds: 20),
      );
      http_.respondWith((_) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return http.Response('{}', 200);
      });
      await expectLater(post(), throwsAi<AiTransientException>());
    });

    test('TimeoutException from the client is transient', () async {
      http_.throwError(TimeoutException('slow'));
      await expectLater(post(), throwsAi<AiTransientException>());
    });

    test('SocketException is transient', () async {
      http_.throwError(const SocketException('Failed host lookup'));
      await expectLater(post(), throwsAi<AiTransientException>());
    });

    test('ClientException is transient', () async {
      http_.throwError(http.ClientException('Connection closed'));
      await expectLater(post(), throwsAi<AiTransientException>());
    });
  });

  group('parseRetryAfter', () {
    test('handles seconds, dates and junk', () {
      final now = DateTime.utc(2026, 9, 15, 12);
      expect(parseRetryAfter('5', now: now), const Duration(seconds: 5));
      expect(
        parseRetryAfter('Tue, 15 Sep 2026 12:01:00 GMT', now: now),
        const Duration(minutes: 1),
      );
      expect(
        parseRetryAfter('Tue, 15 Sep 2026 11:00:00 GMT', now: now),
        Duration.zero,
      );
      expect(parseRetryAfter('soon', now: now), isNull);
      expect(parseRetryAfter(null, now: now), isNull);
    });
  });
}
