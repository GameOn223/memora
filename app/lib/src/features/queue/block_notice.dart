import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:memora_core/memora_core.dart';

import '../../routing/router.dart';

/// What a queue block says, and the one thing that gets past it.
///
/// The queue banner and the toast shown right after images are added both
/// read from here, so a blocked queue says the same thing in both places.
@immutable
class BlockNotice {
  const BlockNotice({
    required this.sentence,
    required this.action,
    required this.route,
  });

  /// Nothing is chosen for vision, so no image can be read.
  BlockNotice.noVisionProvider()
    : this(
        sentence:
            'No vision model is selected, so nothing will be understood '
            'yet.',
        action: 'Choose one',
        route: Routes.capability(Capability.vision),
      );

  /// Local-only mode refuses the chosen provider.
  const BlockNotice.blockedByLocalOnly(String providerName)
    : this(
        sentence:
            'Local-only mode blocks $providerName, so nothing is being '
            'understood.',
        action: 'Open settings',
        route: Routes.settings,
      );

  /// The provider will not take the work as configured. [keyProviderId] is
  /// set when that provider needs an API key, so the action can open the
  /// key screen instead of the provider list.
  BlockNotice.configurationProblem(String message, {String? keyProviderId})
    : this(
        sentence: _closed(message),
        action: keyProviderId == null ? 'Choose another' : 'Fix key',
        route: keyProviderId == null
            ? Routes.capability(Capability.vision)
            : Routes.providerKey(keyProviderId),
      );

  /// The provider is throttling. The queue waits and picks up again at
  /// [retryAt] on its own, so the only thing left to decide is whether to
  /// use something else in the meantime.
  BlockNotice.rateLimited(String providerName, DateTime retryAt)
    : this(
        sentence:
            '$providerName is rate limiting. Retrying at '
            '${DateFormat('HH:mm').format(retryAt.toLocal())}.',
        action: 'Choose another',
        route: Routes.capability(Capability.vision),
      );

  /// The provider is selected but has nothing that can read an image with
  /// the chosen model, so the pick itself has to change.
  BlockNotice.providerUnavailable(String providerName, String? modelId)
    : this(
        sentence: modelId == null
            ? '$providerName cannot understand images.'
            : '$providerName has nothing that can run $modelId.',
        action: 'Change model',
        route: Routes.capability(Capability.vision),
      );

  /// One sentence in plain words: what happened, and what it means.
  final String sentence;

  /// Label of the link beside the sentence.
  final String action;

  /// Where the link goes.
  final String route;

  static String _closed(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return 'The vision provider refused the work.';
    return '.!?'.contains(trimmed[trimmed.length - 1]) ? trimmed : '$trimmed.';
  }
}

/// The notice for [block]. [providers] is used to find the provider a
/// configuration problem names, so its action can open that provider's key
/// screen.
///
/// Every `QueueBlock` has an arm here. `QueueBlock` is sealed, so a new
/// block type in memora_core breaks this switch until its arm is added.
BlockNotice blockNotice(QueueBlock block, {ProviderRegistry? providers}) =>
    switch (block) {
      NoVisionProvider() => BlockNotice.noVisionProvider(),
      BlockedByLocalOnly(:final providerName) => BlockNotice.blockedByLocalOnly(
        providerName,
      ),
      ProviderConfigurationProblem(:final providerName, :final message) =>
        BlockNotice.configurationProblem(
          message,
          keyProviderId: keyProviderId(providers, providerName),
        ),
      RateLimited(:final providerName, :final retryAt) =>
        BlockNotice.rateLimited(providerName, retryAt),
      ProviderUnavailable(:final providerName, :final modelId) =>
        BlockNotice.providerUnavailable(providerName, modelId),
    };

/// The id of the provider called [providerName], when it is one that needs
/// an API key. Null when no such provider is registered, which keeps the
/// notice on the provider list instead of a key screen that may not exist.
String? keyProviderId(ProviderRegistry? providers, String providerName) {
  for (final descriptor
      in providers?.descriptors ?? const <ProviderDescriptor>[]) {
    if (descriptor.displayName == providerName && descriptor.requiresApiKey) {
      return descriptor.id;
    }
  }
  return null;
}
