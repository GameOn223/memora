import '../model/processing.dart';

/// Errors raised by provider adapters. The queue decides what to do based on
/// the subtype. See docs/architecture.md, section 5.3.
sealed class AiException implements Exception {
  const AiException(this.message, {this.providerId});

  final String message;
  final String? providerId;

  @override
  String toString() => '$runtimeType($providerId): $message';
}

/// Worth retrying later: timeouts, rate limits, server errors, no network.
///
/// [retryAfter] is the provider's own hint about when to come back, read from
/// a `Retry-After` header or the equivalent. The queue schedules from it when
/// it is there, so a provider that knows its own limits is believed over the
/// local backoff ladder.
base class AiTransientException extends AiException {
  const AiTransientException(
    super.message, {
    super.providerId,
    this.retryAfter,
  });

  final Duration? retryAfter;
}

/// The provider is rate limiting Memora, for example an HTTP 429.
///
/// Transient like its parent, so anything that catches
/// [AiTransientException] still handles it. The queue treats it differently:
/// a rate limit says something about the provider rather than about the
/// image, so the attempt is given back instead of counting toward the
/// failure cap, and the whole queue waits instead of moving on to the next
/// memory.
final class AiRateLimitException extends AiTransientException {
  const AiRateLimitException(
    super.message, {
    super.providerId,
    super.retryAfter,
  });
}

/// The user needs to fix settings: bad key, unknown model, missing permission.
final class AiConfigurationException extends AiException {
  const AiConfigurationException(super.message, {super.providerId});
}

/// The provider could not handle this particular input.
final class AiContentException extends AiException {
  const AiContentException(super.message, {super.providerId});
}

/// Why a capability can't be used right now.
enum UnavailableReason {
  notConfigured,
  blockedByLocalOnly,
  missingApiKey,
  modelNotDownloaded,
  unsupportedByProvider,
}

/// Thrown by the capability router instead of returning a service.
final class CapabilityUnavailableException implements Exception {
  const CapabilityUnavailableException(
    this.capability,
    this.reason, {
    this.providerName,
    this.modelId,
  });

  final Capability capability;
  final UnavailableReason reason;
  final String? providerName;

  /// The model the user picked, when there was one. Lets the UI name it in
  /// "Fake AI has nothing that can run gemma-3n".
  final String? modelId;

  @override
  String toString() =>
      'CapabilityUnavailableException(${capability.key}, ${reason.name})';
}
