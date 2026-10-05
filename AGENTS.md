# Working in this repository

Notes for coding agents and for anyone who wants the short version of how Memora is built. The long version is [docs/architecture.md](docs/architecture.md), and the human-facing rules are in [CONTRIBUTING.md](CONTRIBUTING.md).

## What this is

Memora is an Android app that turns images you choose to keep into a private, searchable memory you can ask questions about. Everything lives on the phone. The AI provider is the user's choice, including on-device.

```
app/                   Flutter app, and the Android layer in app/android
packages/memora_core      domain model, ports, pipeline, retrieval, chat agent (pure Dart)
packages/memora_database  SQLite, FTS5, vectors, migrations
packages/memora_providers AI provider adapters
docs/                  architecture, providers, export format, device testing, releasing
```

Business logic is pure Dart so it can be tested without a phone. Kotlin handles capture, gallery access, background work, OCR, on-device inference and the Keystore. The two sides meet at a Pigeon bridge.

## Setup

```bash
flutter pub get          # once, at the repo root, resolves the whole workspace
```

Requires Flutter 3.47, an Android SDK with platform 36 and NDK 28.2.13676358, and JDK 17.

## The checks

Run what CI runs before you call anything done:

```bash
dart format --output=none --set-exit-if-changed packages app/lib app/test app/pigeons
dart analyze --fatal-infos packages
(cd app && flutter analyze --fatal-infos lib test)
(cd packages/memora_core && dart test)
(cd packages/memora_database && dart test)
(cd packages/memora_providers && dart test)
(cd app && flutter test)
```

Two traps worth knowing:

- **`flutter analyze` needs its paths.** Run it as `flutter analyze --fatal-infos lib test` from `app/`. Without them the workspace `analysis_options.yaml`, which excludes `app/**`, wins and the command passes while analyzing nothing.
- **Do not run `flutter test` and an APK build at the same time.** Both take the native assets build lock, and the loser fails with a timeout that looks like a real error.

## Rules that are enforced in review

1. No vendor-specific logic in `memora_core`. Providers live in `memora_providers`.
2. The original image is never modified. Anything a model produced can be deleted and regenerated.
3. Adding images never waits on AI.
4. The chat model reaches data only through the typed read-only tools. It never writes SQL.
5. Nothing leaves the device unless the user picked a provider that sends it, and local-only mode is never bypassed.
6. Embeddings carry their model id, version and dimensions. Vectors from different models are never compared.
7. User data stays exportable.

If a change needs to bend one of these, say so in the pull request and explain why.

## Conventions

- **Commits** follow [Conventional Commits](https://www.conventionalcommits.org/) with a scope when it helps: `fix(database): keep the FTS row in sync on reprocess`. Plain messages, no trailers.
- **Tests come first.** New behavior needs a test. A bug fix needs a test that failed before the fix. Tests never call a real AI API or the network; provider tests use recorded fixtures with a mock HTTP client.
- **Migrations are append-only.** Never edit a migration that has shipped. Add the next numbered file in `packages/memora_database/lib/src/migrations/` and a test that upgrades from the previous version.
- **The bridge is generated.** After editing `app/pigeons/messages.dart`, run `cd app && dart run pigeon --input pigeons/messages.dart && dart format lib/src/platform`, and commit the definition with both generated files.
- **Adding a provider** is a descriptor, a client, capability services and fixture-based tests. [docs/providers.md](docs/providers.md) walks through it. Model ids and per-model quirks live in one dated table in `packages/memora_providers/lib/src/shared/model_facts.dart`, because that kind of fact goes stale.
- **UI** takes colors, spacing and type from the theme. The accent is used as an outline, a line or a small mark, never as a flood. Headings stay at weight 500. Icon-only buttons need semantics labels, and touch targets need 48dp even when the design draws something smaller.

## Writing style

This applies to UI copy, documentation, comments and pull request text.

Short, plain sentences. Say what happened and what the person can do next. No em dashes, no exclamation marks, no marketing voice. Avoid "delve", "leverage", "robust" and "seamless". Let sentence length vary rather than making every line the same shape.

## What cannot be tested on a laptop

Capture through the Quick Settings tile, the accessibility screenshot path, MediaProjection, the share sheet, gallery permissions, WorkManager waking the headless engine, ML Kit OCR, ONNX inference, the Keystore and the system save dialog all need a real device. [docs/testing-on-device.md](docs/testing-on-device.md) is the checklist. If your change touches any of them, say in the pull request what you could not verify.

## Questions

Open an issue, or email jayrathod.dev@gmail.com for anything that should stay private.
