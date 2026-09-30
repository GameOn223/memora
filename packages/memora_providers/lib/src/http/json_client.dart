import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException;

import 'package:http/http.dart' as http;
import 'package:memora_core/memora_core.dart';

import 'errors.dart';

/// Sends JSON requests to a provider and turns every failure into an
/// [AiException] the queue knows how to handle.
///
/// The inner client belongs to the caller and is never closed here. Header
/// values that carry credentials are scrubbed from any error message.
class JsonClient {
  JsonClient(this._inner, {this.timeout = const Duration(seconds: 90)});

  final http.Client _inner;

  /// Limit for the whole exchange, including reading the body.
  final Duration timeout;

  Future<Map<String, Object?>> post(
    Uri url,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
    required String providerId,
  }) {
    return _send(
      () => _inner.post(
        url,
        headers: {
          'content-type': 'application/json',
          'accept': 'application/json',
          ...headers,
        },
        body: jsonEncode(body),
      ),
      headers: headers,
      providerId: providerId,
    );
  }

  Future<Map<String, Object?>> get(
    Uri url, {
    Map<String, String> headers = const {},
    required String providerId,
  }) {
    return _send(
      () =>
          _inner.get(url, headers: {'accept': 'application/json', ...headers}),
      headers: headers,
      providerId: providerId,
    );
  }

  Future<Map<String, Object?>> _send(
    Future<http.Response> Function() request, {
    required Map<String, String> headers,
    required String providerId,
  }) async {
    final secrets = _secretValues(headers);
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw AiTransientException(
        'The provider did not answer within ${timeout.inSeconds} s',
        providerId: providerId,
      );
    } on IOException catch (e) {
      throw AiTransientException(
        _transportMessage(e.toString(), secrets),
        providerId: providerId,
      );
    } on http.ClientException catch (e) {
      throw AiTransientException(
        _transportMessage(e.message, secrets),
        providerId: providerId,
      );
    }

    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      final message = providerErrorMessage(text);
      throw exceptionForStatus(
        status,
        providerId: providerId,
        detail: message == null
            ? null
            : shortenDetail(redactSecrets(message, secrets)),
        retryAfter: parseRetryAfter(response.headers['retry-after']),
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw AiTransientException(
        'The provider sent a response that is not JSON',
        providerId: providerId,
      );
    }
    if (decoded is! Map) {
      throw AiTransientException(
        'The provider sent an unexpected JSON response',
        providerId: providerId,
      );
    }
    return decoded.cast<String, Object?>();
  }

  static List<String> _secretValues(Map<String, String> headers) {
    const credentialHeaders = {
      'authorization',
      'x-api-key',
      'x-goog-api-key',
      'api-key',
    };
    return [
      for (final e in headers.entries)
        if (credentialHeaders.contains(e.key.toLowerCase())) ...[
          e.value,
          e.value.replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), ''),
        ],
    ];
  }

  static String _transportMessage(String raw, List<String> secrets) =>
      'Could not reach the provider: '
      '${shortenDetail(redactSecrets(raw, secrets))}';
}
