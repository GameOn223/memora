import 'dart:convert';
import 'dart:io' show HttpDate, HttpException;

import 'package:memora_core/memora_core.dart';

/// Longest provider message copied into an exception.
const maxProviderDetailLength = 200;

/// Phrases that mean the provider rejected this particular picture rather
/// than the shape of the request.
///
/// Kept narrow on purpose. A content error fails the memory for good, so an
/// ambiguous 400 is better treated as configuration, which pauses the queue
/// once and can be fixed. Bare "content" and "size" are left out because
/// they show up in ordinary validation messages such as
/// `Invalid value for 'messages[0].content'`.
final _contentHints = RegExp(
  r'\bimages?\b|\bsafety\b|\bmoderation\b|\bpolicy\b|\bblocked\b|'
  r'content filter|content policy|content filtering|too large|'
  r'unsupported image|cannot process image|could not process image',
  caseSensitive: false,
);

final _keyShapes = RegExp(
  r'(sk-ant-[A-Za-z0-9_\-]{8,}|sk-[A-Za-z0-9_\-]{8,}|nvapi-[A-Za-z0-9_\-]{8,}|'
  r'gsk_[A-Za-z0-9]{8,}|AIza[0-9A-Za-z_\-]{20,})',
);

/// Pulls a readable message out of a provider error body, or null when the
/// body isn't JSON or has no message.
///
/// Understands the common shapes: `{"error": {"message": ...}}` (OpenAI,
/// Anthropic, Gemini), `{"error": "..."}` (Ollama), `{"detail": ...}`
/// (NVIDIA and FastAPI servers) and a list wrapping any of these.
String? providerErrorMessage(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  return _messageFrom(decoded);
}

String? _messageFrom(Object? value, [int depth = 0]) {
  if (depth > 4) return null;
  switch (value) {
    case final String s:
      final trimmed = s.trim();
      return trimmed.isEmpty ? null : trimmed;
    case final Map<Object?, Object?> m:
      for (final key in const ['error', 'message', 'detail', 'msg', 'title']) {
        final found = _messageFrom(m[key], depth + 1);
        if (found != null) return found;
      }
      return null;
    case final List<Object?> l when l.isNotEmpty:
      return _messageFrom(l.first, depth + 1);
    default:
      return null;
  }
}

/// Replaces [secrets] and anything shaped like a known API key.
String redactSecrets(String text, Iterable<String> secrets) {
  var result = text;
  for (final secret in secrets) {
    if (secret.length >= 6) result = result.replaceAll(secret, '[redacted]');
  }
  return result.replaceAll(_keyShapes, '[redacted]');
}

/// Collapses whitespace and cuts [text] to [maxProviderDetailLength].
String shortenDetail(String text) {
  final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.length <= maxProviderDetailLength) return collapsed;
  return '${collapsed.substring(0, maxProviderDetailLength - 3)}...';
}

/// Reads a `Retry-After` header given in seconds or as an HTTP date.
Duration? parseRetryAfter(String? value, {DateTime? now}) {
  if (value == null) return null;
  final trimmed = value.trim();
  final seconds = int.tryParse(trimmed);
  if (seconds != null) return Duration(seconds: seconds < 0 ? 0 : seconds);
  try {
    final at = HttpDate.parse(trimmed);
    final wait = at.difference(now ?? DateTime.now());
    return wait.isNegative ? Duration.zero : wait;
  } on HttpException {
    return null;
  } on FormatException {
    return null;
  }
}

/// Classifies an HTTP error status. See docs/architecture.md, section 5.3.
AiException exceptionForStatus(
  int status, {
  required String providerId,
  String? detail,
  Duration? retryAfter,
}) {
  String withDetail(String base) =>
      detail == null || detail.isEmpty ? base : '$base: $detail';

  switch (status) {
    case 401:
      // The provider's own text often echoes part of the key, so leave it out.
      return AiConfigurationException(
        'The API key was rejected',
        providerId: providerId,
      );
    case 403:
      return AiConfigurationException(
        withDetail('The API key was rejected'),
        providerId: providerId,
      );
    case 404:
      return AiConfigurationException(
        withDetail('Model or endpoint not found'),
        providerId: providerId,
      );
    case 402:
      return AiConfigurationException(
        withDetail('The provider refused the request for billing reasons'),
        providerId: providerId,
      );
    case 413:
      return AiContentException(
        withDetail('The request was too large for the provider'),
        providerId: providerId,
      );
    case 400 || 422:
      if (detail != null && _contentHints.hasMatch(detail)) {
        return AiContentException(
          withDetail('The provider could not process this input'),
          providerId: providerId,
        );
      }
      return AiConfigurationException(
        withDetail('The provider rejected the request'),
        providerId: providerId,
      );
    case 429:
      // Its own subtype, so the queue can wait without charging the memory
      // an attempt. See docs/architecture.md, section 5.3.
      return AiRateLimitException(
        withDetail('Rate limited by the provider'),
        providerId: providerId,
        retryAfter: retryAfter,
      );
    case 408 || 409 || 425:
      return AiTransientException(
        withDetail('The provider asked to try again later ($status)'),
        providerId: providerId,
        retryAfter: retryAfter,
      );
  }
  if (status >= 500) {
    return AiTransientException(
      withDetail('The provider is having trouble ($status)'),
      providerId: providerId,
      retryAfter: retryAfter,
    );
  }
  if (status >= 400) {
    return AiConfigurationException(
      withDetail('Unexpected response from the provider ($status)'),
      providerId: providerId,
    );
  }
  return AiTransientException(
    'Unexpected response from the provider ($status)',
    providerId: providerId,
  );
}
