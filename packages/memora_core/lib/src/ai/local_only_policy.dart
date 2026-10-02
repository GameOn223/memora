import 'provider.dart';

/// Decides which providers local-only mode allows.
///
/// On-device providers always pass. Cloud providers never do. Self-hosted
/// providers pass only when their base URL points at this device or a private
/// network. See docs/architecture.md, section 7.3.
class LocalOnlyPolicy {
  const LocalOnlyPolicy();

  bool allows(ProviderDescriptor descriptor, String? baseUrl) {
    switch (descriptor.location) {
      case ProviderLocation.onDevice:
        return true;
      case ProviderLocation.cloud:
        return false;
      case ProviderLocation.selfHosted:
        if (baseUrl == null) return false;
        final uri = Uri.tryParse(baseUrl.trim());
        if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
        return isPrivateHost(uri.host);
    }
  }

  /// True for loopback, private and link-local addresses and `.local` names.
  static bool isPrivateHost(String rawHost) {
    final host = rawHost.toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '');
    if (host == 'localhost' || host.endsWith('.local')) return true;

    final v4 = _parseIpv4(host);
    if (v4 != null) {
      final [a, b, _, _] = v4;
      return a == 127 ||
          a == 10 ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          (a == 169 && b == 254);
    }

    if (host.contains(':')) {
      if (host == '::1') return true;
      final firstGroup = host.split(':').first;
      final value = int.tryParse(firstGroup, radix: 16);
      if (value == null) return false;
      final isUniqueLocal = (value & 0xfe00) == 0xfc00;
      final isLinkLocal = (value & 0xffc0) == 0xfe80;
      return isUniqueLocal || isLinkLocal;
    }
    return false;
  }

  static List<int>? _parseIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return null;
    final octets = <int>[];
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) return null;
      octets.add(n);
    }
    return octets;
  }
}
