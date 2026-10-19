# Contributing to Prism

Thanks for helping. Bug reports, fixes, tests and documentation are all welcome. For a new feature, open an issue first so we can agree on the shape before you build it.

## Set up

You need a Mac with Xcode 27. The app targets iOS 27, iPadOS 27, macOS 27 and visionOS 27. Xcode 27 brings the Swift 6 toolchain; the packages compile in Swift 6 language mode and the app target in Swift 5 mode.

```bash
git clone https://github.com/soma-intelligence/prism.git
cd prism
open App/Prism.xcodeproj
```

Run the `Prism` scheme on an iOS or visionOS simulator. You don't need a backend, an account, a team or any setup: the build as shipped runs in local mode.

To run on a Mac or a device, copy `App/Config/Signing.example.xcconfig` to `App/Config/Signing.xcconfig` and set `PRISM_DEVELOPMENT_TEAM` (your ten character team id; a free Personal Team should work for a device run, but the maintainers haven't tried it) and a `PRISM_BUNDLE_ID` that's unique to you. HealthKit on a Mac needs its capability on your team and app id too. Change the app group `group.Soma.Prism` as well (both entitlements files and `SnapshotStore.appGroup` in `App/SomaWidgetKit`) before you run on a Mac or a device: automatic signing under another team can't register Soma's group. That file is git ignored; never commit it, or a `Supabase.xcconfig`. Without a team, the Mac build stops on a missing development certificate and the visionOS device build asks for a team. For a command line compile check that needs no signing, add `CODE_SIGNING_ALLOWED=NO`, as the commands below do.

HealthKit returns nothing in the Simulator, so every value shows as a dash. In a Debug build on the Simulator, the Health seeder in `App/Prism/Features/Dev` writes a month of invented samples so you can see the pages with numbers.

## Build and test

From the repository root, the app on all three platforms:

```bash
xcodebuild -project App/Prism.xcodeproj -scheme Prism \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project App/Prism.xcodeproj -scheme Prism \
  -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project App/Prism.xcodeproj -scheme Prism \
  -destination 'generic/platform=visionOS' build CODE_SIGNING_ALLOWED=NO
```

The app's unit tests (use any iPhone simulator you have):

```bash
xcodebuild test -project App/Prism.xcodeproj -scheme Prism \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:PrismTests -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

The packages:

```bash
(cd Packages/SomaUI && swift test)
(cd Packages/WellnessKit && swift test)
(cd App/SomaWidgetKit && swift test)
```

The backend, if you touch `supabase/`:

```bash
supabase/scripts/local-test/run.sh
supabase/scripts/test-functions.sh
```

A change is done when the app builds for iOS, macOS and visionOS and every suite passes. A change to a package isn't verified by the package alone: build the app against it too.

## Design system rules

[CLAUDE.md](CLAUDE.md) holds the full list. The ones reviewers check first:

- Every colour, size, duration and font comes from `SomaTheme`. No literal colours, hard-coded point sizes or `Font.system(...)` in a view.
- Fonts go through `.somaFont(_:)`. `TypographyGuardTests` fails on `.font(spec.font)`, a hand written `.tracking` or `.kerning`, or a font design named at a call site.
- Glass goes through `somaGlass(_:in:)` and its siblings, never `glassEffect` directly, or the visionOS build breaks. `GlassGuardTests` checks it. Never `.interactive()` glass under a button.
- One accent, for action, selection and state only.
- Every animation has a still version when Reduce Motion is on.
- Reuse a component from `Packages/SomaUI` before writing one. A new component lives in the package, takes all its looks from the theme, ships a `#Preview` and gets an entry in `ComponentPlayground`.
- A missing value shows as a dash, never as zero.
- Apple Health is asked once. A new Health type goes into `HealthAccess`, never into a request of its own.

## Writing rules

These cover code, comments, Markdown, commit messages, pull request text and every string the app shows:

- No em dash and no en dash, anywhere.
- No hyphen standing in for a dash between words. Use a colon, a comma, parentheses or two sentences. Hyphens inside words, flags and identifiers are fine.
- Health copy is wellness, not medicine: no diagnosis, no treatment, no "clinically proven". An estimate says it's an estimate and names its source.

`StyleGuardTests` enforces both rules in `App/`. The build workflow also scans every tracked `.md`, `.yml`, `.yaml`, `.json` and `.swift` file in the repository for em and en dashes, and every Markdown file, outside code fences, for a hyphen used as a dash.

GitHub's hosted macOS runners don't have Xcode 27 yet. Until they do, the app and package jobs skip with a notice and pass, while the repository checks above still run on every pull request. Build and run the tests locally before you open one, and paste the test summary in the pull request.

## Privacy

If your change sends anything new off the device, or adds a field to a request that already does, update [PRIVACY.md](PRIVACY.md) in the same pull request. Never commit real health data, in tests, fixtures, screenshots or issues.

## Pull requests

- One change per pull request, with tests where the change has behaviour.
- Say what changed and how you checked it, on which platforms.
- Fill in the pull request template.

## Contributor license agreement

Prism is licensed under the GNU Affero General Public License v3.0. Soma Labs, Inc. also ships Prism through the App Store from its private source, so it needs the right to use outside code there too.

You keep the copyright in what you write. Before your first pull request is merged, you sign the [contributor license agreement](CLA.md), which grants Soma Labs, Inc. the right to use, ship and relicense your contribution, including in its App Store build. Soma asks for this because it builds the App Store version from its private repository, under terms that aren't the AGPL.

Signing takes one comment. When you open your first pull request, the CLA Assistant bot comments on it with a link to the agreement. Read it, then reply on the pull request with this sentence, exactly:

```
I have read the CLA Document and I hereby sign the CLA
```

The bot records your signature and the check turns green. You sign once: it covers that pull request and your later ones. If the check stays red, comment `recheck`.

If you contribute as part of your job, make sure your employer agrees before you sign: many employment contracts give the employer rights in code you write, and the agreement asks you to confirm you have permission. If your company would rather sign for all its employees, a corporate contributor license agreement is available on request: write to security@somalabs.me with "CLA" in the subject.

## How your change reaches the app

Prism is developed in a private repository at Soma, and this repository is exported from it: [EXPORT.json](EXPORT.json) names the commits each export came from. When we merge your pull request here, a maintainer ports it into the private source, and the next export carries it back with the rest of the work. Your pull request stays merged here in the meantime. If the export changed the same lines, the port may look a little different from your diff.

## For maintainers

The exported `App/Prism.xcodeproj/project.pbxproj` is an XML property list, written by the export tool. Xcode reads it and rewrites it in its usual text format the first time it saves the project, which makes a noisy diff once. A maintainer opens the project in Xcode and saves it once before tagging a release, so the first change after that diffs cleanly.

`docs/images/social-preview.png` (1280 by 640) is not shown in the README. Upload it in the GitHub repository settings, under Social preview, so links to the repository show it.

## Conduct

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).
