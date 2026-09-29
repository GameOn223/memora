import 'dart:convert';

import 'package:memora_core/memora_core.dart';

import '../http/errors.dart';
import '../http/json_client.dart';
import 'json_read.dart';

/// Builds the credential headers for a key. Called only with a non-empty key.
typedef AuthHeaders = Map<String, String> Function(String apiKey);

/// One configured provider server: base URL, key, headers and transport.
class ProviderEndpoint {
  ProviderEndpoint({
    required this.providerId,
    required String? baseUrl,
    required this._apiKey,
    required this._http,
    required this._authHeaders,
    this._extraHeaders = const {},
  }) : _baseUrl = baseUrl?.trim();

  final String providerId;
  final String? _baseUrl;
  final String? _apiKey;
  final JsonClient _http;
  final AuthHeaders _authHeaders;
  final Map<String, String> _extraHeaders;

  bool get hasApiKey => (_apiKey ?? '').isNotEmpty;

  bool get hasValidBaseUrl {
    final base = _baseUrl;
    if (base == null || base.isEmpty) return false;
    final uri = Uri.tryParse(base);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// [path] starts with a slash and may carry a query string.
  Uri url(String path) {
    if (!hasValidBaseUrl) {
      throw AiConfigurationException(
        'Set a valid base URL, such as http://192.168.1.20:11434/v1',
        providerId: providerId,
      );
    }
    final base = _baseUrl!.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  Map<String, String> get headers => {
    ..._extraHeaders,
    if (hasApiKey) ..._authHeaders(_apiKey!),
  };

  Future<Map<String, Object?>> post(
    String path,
    Map<String, Object?> body,
  ) async {
    final json = await _http.post(
      url(path),
      body,
      headers: headers,
      providerId: providerId,
    );
    _throwIfError(json);
    return json;
  }

  Future<Map<String, Object?>> get(String path) async {
    final json = await _http.get(
      url(path),
      headers: headers,
      providerId: providerId,
    );
    _throwIfError(json);
    return json;
  }

  /// Some gateways, OpenRouter among them, report upstream failures inside a
  /// 200 response.
  void _throwIfError(Map<String, Object?> json) {
    final error = json['error'];
    if (error == null) return;
    final message = providerErrorMessage(jsonEncode(json));
    final detail = message == null
        ? null
        : shortenDetail(redactSecrets(message, [?_apiKey]));
    final code = asObject(error)?['code'];
    final status = code is int ? code : int.tryParse('$code');
    if (status != null && status >= 400 && status < 600) {
      throw exceptionForStatus(status, providerId: providerId, detail: detail);
    }
    throw AiTransientException(
      detail == null
          ? 'The provider reported an error'
          : 'The provider reported an error: $detail',
      providerId: providerId,
    );
  }
}
