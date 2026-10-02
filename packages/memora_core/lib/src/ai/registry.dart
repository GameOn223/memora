import '../model/processing.dart';
import 'provider.dart';

/// Every provider Memora knows about, with a factory for each.
///
/// The app registers the shipped adapters at startup. Adding a provider means
/// registering one more descriptor and factory; nothing in core changes.
class ProviderRegistry {
  final Map<String, ({ProviderDescriptor descriptor, ProviderFactory factory})>
  _entries = {};

  void register(ProviderDescriptor descriptor, ProviderFactory factory) {
    if (_entries.containsKey(descriptor.id)) {
      throw StateError('Provider "${descriptor.id}" is already registered');
    }
    _entries[descriptor.id] = (descriptor: descriptor, factory: factory);
  }

  List<ProviderDescriptor> get descriptors => [
    for (final e in _entries.values) e.descriptor,
  ];

  ProviderDescriptor? descriptor(String id) => _entries[id]?.descriptor;

  List<ProviderDescriptor> supporting(Capability capability) =>
      descriptors.where((d) => d.supports(capability)).toList();

  ProviderClient create(ProviderConfig config) {
    final entry = _entries[config.providerId];
    if (entry == null) {
      throw ArgumentError.value(
        config.providerId,
        'providerId',
        'Not registered',
      );
    }
    return entry.factory(config);
  }
}
