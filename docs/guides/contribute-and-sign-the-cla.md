# How do I contribute to Prism, and what is the CLA?

Open an issue first for a new feature, then send a pull request that builds for iOS, macOS and visionOS with every test suite passing. Before your first pull request is merged you sign Soma Labs' contributor license agreement by replying to the CLA Assistant bot with one fixed sentence. You keep the copyright; the agreement lets Soma Labs, Inc. also ship your contribution in its App Store build.

## Steps

1. Read [CONTRIBUTING.md](../../CONTRIBUTING.md) and [AGENTS.md](../../AGENTS.md).
2. For a new feature, open an issue so the shape is agreed before you build. Bug fixes, tests and docs can go straight to a pull request.
3. Build on all three platforms and run the tests (commands in [build from source](build-from-source-with-xcode.md)).
4. Open the pull request, fill in the template, and paste the test summary: GitHub's hosted runners don't have Xcode 27 yet, so the app and package jobs skip there.
5. When the CLA Assistant bot comments, read [CLA.md](../../CLA.md) and reply with exactly:

   ```
   I have read the CLA Document and I hereby sign the CLA
   ```

   You sign once. If the check stays red, comment `recheck`.

## What reviewers check first

- Colours, sizes, durations and fonts come from `SomaTheme`, fonts through `.somaFont(_:)`, glass through `somaGlass(_:in:)`.
- A missing value shows as a dash, never zero.
- Apple Health is asked once: a new type goes into `HealthAccess`.
- A new network request, or a new field in one, updates [PRIVACY.md](../../PRIVACY.md) in the same pull request.
- No em dash or en dash anywhere, and no hyphen standing in for a dash in prose. `StyleGuardTests` and the build workflow enforce it.
- Health copy stays wellness: no medical claims, and an estimate names its published source.
- Never commit real health data, `Signing.xcconfig` or `Supabase.xcconfig`.

## Why there's a CLA

Prism here is AGPL-3.0. Soma Labs also builds the App Store version from a private repository under other terms, so it needs the right to use outside code there too. If you contribute as part of your job, check with your employer first. A corporate agreement is available on request at security@somalabs.me with "CLA" in the subject.

## How a merged change reaches the app

This repository is exported from Soma's private source ([EXPORT.json](../../EXPORT.json) names the commits). A maintainer ports a merged pull request into the private source, and the next export carries it back.

## Related

- [Build Prism from source with Xcode](build-from-source-with-xcode.md)
- [CODE_OF_CONDUCT.md](../../CODE_OF_CONDUCT.md), [SECURITY.md](../../SECURITY.md)
- [README](../../README.md)
