# Releasing Memora

Memora ships as APKs attached to a GitHub release. There is no Play listing yet, so the checksums published with the release are how people verify a download.

## Versioning

`app/pubspec.yaml` holds the version, for example `0.1.0+1`. The part before `+` is the version name, the part after is the version code. Bump the version code on every build you publish, even a rebuild of the same version name.

Memora follows semantic versioning. A release that changes the export format or the database schema says so in `CHANGELOG.md`.

## One-time: the signing key

Release builds are signed with a key you keep outside the repository. Create one with the JDK that ships with Android Studio:

```bash
keytool -genkey -v \
  -keystore ~/memora-release.jks \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -alias memora
```

Store the keystore and its passwords in a password manager. Losing the key means future releases can't upgrade an installed app.

Then write `app/android/key.properties`:

```properties
storeFile=C:\\Users\\you\\memora-release.jks
storePassword=<store password>
keyAlias=memora
keyPassword=<key password>
```

`key.properties` and `*.jks` are in `.gitignore`. Never commit either. Without `key.properties`, release builds fall back to the debug key, which is fine for local testing and wrong for anything you publish.

## Building

```bash
cd app
flutter pub get
flutter analyze --fatal-infos
flutter test
flutter build apk --release --split-per-abi
```

The APKs land in `app/build/app/outputs/flutter-apk/`:

- `app-arm64-v8a-release.apk` for nearly every phone sold since 2017
- `app-armeabi-v7a-release.apk` for older 32-bit devices
- `app-x86_64-release.apk` for emulators and a few tablets

Check the size of the arm64 APK. A sudden jump usually means a new native dependency.

Install the arm64 build on a real device and work through `docs/testing-on-device.md` before publishing.

## Checksums

```bash
cd app/build/app/outputs/flutter-apk
sha256sum app-*-release.apk > memora-<version>-sha256.txt
```

Attach that file to the release so people can verify what they downloaded.

## Publishing

1. Update `CHANGELOG.md` with what changed, and mention any migration.
2. Commit the version bump and changelog, then tag: `git tag -a v0.1.0 -m "Memora 0.1.0"` and `git push --tags`.
3. Create the release:

```bash
gh release create v0.1.0 \
  app/build/app/outputs/flutter-apk/app-*-release.apk \
  app/build/app/outputs/flutter-apk/memora-0.1.0-sha256.txt \
  --title "Memora 0.1.0" --notes-file release-notes.md
```

4. Say in the notes which Android versions were tested, and that Memora needs no account and sends nothing anywhere unless the user configures a cloud provider.

## After the release

- Bump the version in `app/pubspec.yaml` to the next patch with `+1` on the version code, so nightly builds are never confused with the release.
- Open issues for anything the device checklist turned up.
