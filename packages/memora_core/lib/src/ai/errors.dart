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
final class AiTransientException extends AiException {
  const AiTransientException(
    super.message, {
    super.providerId,
    this.retryAfter,
  });

  final Duration? retryAfter;
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
  });

  final Capability capability;
  final UnavailableReason reason;
  final String? providerName;

  @override
  String toString() =>
      'CapabilityUnavailableException(${capability.key}, ${reason.name})';
}
