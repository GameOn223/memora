import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Reads a file from `test/fixtures/`.
String fixture(String path) => File('test/fixtures/$path').readAsStringSync();

/// Reads and decodes a JSON fixture.
Object? fixtureJson(String path) => jsonDecode(fixture(path));

/// Reads a JSON fixture and swaps placeholder strings for real values, so
/// golden request bodies don't have to repeat long prompts.
Object? fixtureJsonWith(String path, Map<String, Object?> placeholders) =>
    _replace(fixtureJson(path), placeholders);

Object? _replace(Object? value, Map<String, Object?> placeholders) {
  return switch (value) {
    final String s when placeholders.containsKey(s) => placeholders[s],
    final Map<String, Object?> m => {
      for (final e in m.entries) e.key: _replace(e.value, placeholders),
    },
    final List<Object?> l => [for (final v in l) _replace(v, placeholders)],
    _ => value,
  };
}

typedef Responder = Future<http.Response> Function(http.Request request);

/// A mock HTTP client that answers requests from a script, in order, and
/// records what was sent. Nothing touches the network.
class ScriptedHttp {
  ScriptedHttp() {
    client = MockClient((request) async {
      requests.add(request);
      if (_script.isEmpty) {
        fail('Unexpected request: ${request.method} ${request.url}');
      }
      return _script.removeAt(0)(request);
    });
  }

  late final http.Client client;
  final List<http.Request> requests = [];
  final List<Responder> _script = [];

  void reply(Object? json, {int status = 200, Map<String, String>? headers}) {
    replyRaw(jsonEncode(json), status: status, headers: headers);
  }

  void replyFixture(
    String path, {
    int status = 200,
    Map<String, String>? headers,
  }) {
    replyRaw(fixture(path), status: status, headers: headers);
  }

  void replyRaw(String body, {int status = 200, Map<String, String>? headers}) {
    _script.add(
      (_) async => http.Response.bytes(
        utf8.encode(body),
        status,
        headers: {
          'content-type': 'application/json; charset=utf-8',
          ...?headers,
        },
      ),
    );
  }

  void throwError(Object error) {
    _script.add((_) async => throw error);
  }

  void respondWith(Responder responder) => _script.add(responder);

  /// Decoded JSON body of request [index].
  Map<String, Object?> body(int index) =>
      (jsonDecode(requests[index].body) as Map).cast<String, Object?>();

  bool get exhausted => _script.isEmpty;
}
