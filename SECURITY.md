# Security policy

Memora keeps personal images, extracted text and API keys on the phone. We take reports about any of that seriously.

## Supported versions

Security fixes go into the latest release. Please check that your report applies to the newest version before sending it.

## Reporting a vulnerability

Please don't open a public issue for security problems.

Report privately through GitHub's **Report a vulnerability** button on the repository's Security tab. If that option isn't available to you, contact the maintainer (@GameOn223) privately on GitHub and we'll set up a private channel.

Include as much of this as you can:

- what the problem is and what an attacker could do with it
- the Memora version, Android version and device
- steps to reproduce, or a proof of concept
- whether the issue needs a particular provider or setting (local-only mode, overnight processing, accessibility capture)

We'll acknowledge your report within 7 days and keep you updated while we work on a fix. Once it's released, we're happy to credit you in the release notes unless you'd rather stay anonymous.

## What we especially want to hear about

- API keys readable outside the Keystore-backed store, or showing up in logs, exports or crash reports
- any way data reaches a provider the user didn't select, or gets past local-only mode
- the chat model reading or changing data beyond its read-only tools
- the accessibility capture service doing anything other than taking a screenshot after a tile tap
- other apps reading Memora's images, database or export files
- memory deletion leaving images, thumbnails, vectors or index rows behind

## Out of scope

- What a cloud AI provider does with data after the user chose to send it there. That's governed by the provider's own terms.
- Attacks that need a rooted phone or an unlocked, already compromised device.
