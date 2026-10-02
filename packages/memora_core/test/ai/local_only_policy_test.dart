import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

ProviderDescriptor _descriptor(ProviderLocation location) => ProviderDescriptor(
  id: 'p',
  displayName: 'P',
  location: location,
  capabilities: const {Capability.chat},
);

void main() {
  const policy = LocalOnlyPolicy();

  test('on-device providers are always allowed', () {
    expect(policy.allows(_descriptor(ProviderLocation.onDevice), null), isTrue);
  });

  test('cloud providers are never allowed', () {
    expect(
      policy.allows(_descriptor(ProviderLocation.cloud), 'http://localhost'),
      isFalse,
    );
  });

  group('self-hosted providers', () {
    final selfHosted = _descriptor(ProviderLocation.selfHosted);

    for (final url in [
      'http://localhost:11434',
      'http://127.0.0.1:1234/v1',
      'http://[::1]:8080',
      'http://10.0.2.2:11434',
      'http://172.16.4.2',
      'http://172.31.255.1',
      'http://192.168.1.20:11434/v1',
      'http://169.254.10.1',
      'http://[fd12:3456::1]:8000',
      'http://[fe80::1]',
      'http://studio.local:1234',
    ]) {
      test('allows private host $url', () {
        expect(policy.allows(selfHosted, url), isTrue);
      });
    }

    for (final url in [
      'https://api.openai.com/v1',
      'http://172.32.0.1',
      'http://8.8.8.8',
      'http://192.169.1.1',
      'https://my-ollama.example.com',
      'not a url',
      '',
    ]) {
      test('refuses public or invalid host "$url"', () {
        expect(policy.allows(selfHosted, url), isFalse);
      });
    }

    test('refuses a missing base URL', () {
      expect(policy.allows(selfHosted, null), isFalse);
    });
  });

  test('isPrivateHost is exposed for the settings screen', () {
    expect(LocalOnlyPolicy.isPrivateHost('192.168.0.5'), isTrue);
    expect(LocalOnlyPolicy.isPrivateHost('example.com'), isFalse);
  });
}
