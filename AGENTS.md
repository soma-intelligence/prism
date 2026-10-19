# AGENTS.md: Prism

Guidance for coding agents, and for people, working in this repository.

Prism is a native health app. Swift 6 toolchain (packages in Swift 6 language
mode, the app target in Swift 5 mode), SwiftUI, SwiftData, HealthKit. The Xcode
project is `App/Prism.xcodeproj`, the app target `Prism`. Entry:
`App/Prism/PrismApp.swift`.

Deployment target iOS 27 and macOS 27 (the Ask tab's `.prominent` role is
iOS 27 API), and the target also builds for macOS and visionOS (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx xros xrsimulator`,
`TARGETED_DEVICE_FAMILY = 1,2,7`). A change that only compiles on iPhone is not
done.

## Writing rules

These apply to every character this repo produces: source, comments, doc
comments, commit messages, pull request bodies, Markdown, and any string the app
shows a person.

- **Never write an em dash (`U+2014`) or an en dash (`U+2013`).** Not in prose, not in a
  comment, not in UI copy. `App/PrismTests/StyleGuardTests.swift` fails the build
  when one appears. The characters are named by code point here on purpose: a
  rule that spells itself out with the glyph it forbids trips its own guard,
  which is how this line was written the first time.
- **Never use a hyphen as punctuation** (a hyphen between two spaces, standing in for a dash). Write the
  sentence with a colon, a comma, a semicolon, parentheses, or two sentences.
  Enforced on prose only, which is comments and Markdown: subtracting one value
  from another is arithmetic, and a rule that cannot tell the two apart would
  ban the minus sign.
- Hyphens inside a word stay: `kebab-case`, `pull-to-refresh`, `top-centered`,
  CLI flags, identifiers, and anything inside a code fence or a string literal
  that has to match something exactly.
- When a dash is what the sentence wants, a colon is almost always the right
  replacement: the clause after it explains the clause before it.
- Minus signs, ranges in code (`0...5`), and negative numbers are untouched by
  the rule.

`StyleGuardTests` walks `App/`. The build workflow in `.github/workflows`
also scans every tracked `.md`, `.yml`, `.yaml`, `.json` and `.swift` file for
em and en dashes, and every Markdown file, outside code fences, for a hyphen
used as a dash.

Health copy is wellness, not medicine: no diagnosis, no treatment, no
"clinically proven". An estimate (biological age, PREVENT risk) says it is an
informational estimate and names its published source.

## Architecture

The app is thin. Nearly everything reusable lives in a local package.

```
App/
  Prism/                   the app target
    App/                   lifecycle, theme and Health injection
    Core/                  models, stores and engines: Health, Scoring, Lab, Tools, Cloud, Ask, Account
    Features/<Name>/       one folder per surface: Pulse, Longevity, Track, Ask, Tools, Vault, Settings
    Features/Shared/       PageScaffold, the tab pages' top bar, the page-level cards
    Features/Dev/          ComponentPlayground (the component gallery) and the Health seeder
  SomaWidgets/             the widget extension (iOS)
  SomaWidgetKit/           local package shared by the app and the widgets
  PrismTests/              unit tests, including the style, glass and typography guards
  PrismUITests/
  Config/                  Prism.xcconfig, Cloud.xcconfig, Signing.example.xcconfig
Packages/
  SomaUI/                  the design system package
  WellnessKit/             the sync and Apple Health packages
supabase/                  the backend: migrations, Edge Functions, SQL tests
```

### SomaUI (`Packages/SomaUI`, local SPM)

The design system. Two products: `SomaUI` ships, `SomaUIPreviewSupport` holds the
preview fixtures and must never be imported by a user-facing surface.

`SomaTheme` is a `Sendable`, `Equatable` struct injected through the environment
(`.somaTheme(_:)`). Components read it with `@Environment(\.somaTheme)`; they
never take a colour, a measurement or a string of copy as a parameter.

### WellnessKit (`Packages/WellnessKit`, local SPM)

`SyncCore` and `SyncSupabase` are the sync foundation. `HealthExportCore` holds
the 192 entry metric catalog, the canonical units, the permission scoping and the
`HealthSampleSource` contract, with no platform dependency.
`HealthExportHealthKit` is the reader behind that contract.
`HealthScoring` holds `SomaScoringEngine`, which calculates sleep, recovery,
strain, stress and energy. `SomaScores` applies the app's data gates before
showing those results. `HealthCloud` uploads Health samples for a signed in
person.

## Hard rules

- **Read the design system before writing a view.** Every colour, size, duration
  and font comes from `SomaTheme`. A literal colour, a hard-coded point size or a
  `Font.system(...)` call inside a view is a defect to fix.
- **One type family.** `SomaFontFamily` has one case: SF Pro, for words and
  numbers alike (regular weight, tight tracking). Numbers hold their columns
  through tabular digits on the number roles, `metric` and `rowValue`. To add a
  face, edit that enum. A `Font.Design` passed at a call site is a defect.
- **A role is a font and its tracking.** Apply it with `.somaFont(_:)`, never
  with `.font(spec.font)` alone, which drops the tracking, and never with a
  hand written `.tracking` or `.kerning`. `TypographyGuardTests` fails on those
  forms, and on a font design named at a call site.
- **Liquid Glass is inert chrome.** Never `.interactive()` under a button: the
  glass swallows the tap. Press feedback is `SomaGlassPressStyle`, which is a
  scale and a dim read off the theme. Glass is not laid on glass either, with one
  sanctioned exception: the tab bar's selection bubble, which is a glass shape
  carrying a `glassEffectID` so the container morphs it between tabs.
- **Glass goes through `somaGlass(_:in:)`.** visionOS has no Liquid Glass:
  `glassEffect`, `GlassEffectContainer` and the `glassEffectID`,
  `glassEffectUnion` and `glassEffectTransition` modifiers are unavailable
  there, so one direct call breaks the headset build while every iPhone build
  stays green. SomaUI's `somaGlass(_:in:)`, `SomaGlassContainer`, `somaGlassID`,
  `somaGlassUnion` and `somaGlassTransition` draw the system's glass on iOS and
  macOS, unchanged, and the regular material on visionOS. `GlassGuardTests`,
  in the app and in the package, fails on a direct call.
- **One accent.** It carries action, selection and state, never decoration, and
  never more than a fraction of a screen. Selection is a tonal step; the accent
  rides the glyph and the label.
- **Every animation needs a still counterpart.** Check
  `@Environment(\.accessibilityReduceMotion)` and settle the element rather than
  leaving it mid-loop.
- **Reuse before you create.** Look in `Packages/SomaUI/Sources/SomaUI/Components`
  and in the target feature's folder first. A new component is justified only
  when nothing fits, and then it is driven entirely by its inputs and the theme,
  lives in the package, ships a `#Preview`, and gets an entry in
  `ComponentPlayground`.
- **Fixtures are shared.** Previews and the gallery both draw from
  `SomaPreviewSamples`. Never inline sample data in a component.
- **A missing value renders as a dash, never as zero.** `HealthDashboard`
  returns `nil` when the store holds nothing, and the page says so. An empty
  page with no explanation looks broken to the person reading it.
- **Apple Health asks once.** The permission sheet appears one time, not per
  surface. `HealthAccess` asks for every type the app reads and writes in a
  single request, the first time anything needs Health
  (`HealthDashboard.request`). A new read or write type goes into
  `HealthAccess`, never into a request of its own, or the sheet comes back. The
  sensitive metrics sit in that sheet with their switches off. The iPhone's
  Motion & Fitness question (steps, distance, floors and activity counted by the
  phone without a watch, `Core/Motion/PhoneMotion`) rides the same moment:
  `HealthAccess.requestEverything` puts it right after Health's sheet, through
  `PhoneMotion.requestAccess()`. Core Motion has no request call, the first read
  of the step counter is the question, so nothing else reads Core Motion before
  that answer.
- **Nothing leaves the device without a reason in `PRIVACY.md`.** A new network
  request, or a new field in an existing one, updates that page in the same
  pull request.
- **Concurrency is actors plus async/await.** No Combine, no callback pyramids.
  Swift 6 language mode is on in both packages.

## Platform behaviour

One `TabView` serves every context. On a phone it draws the native Liquid Glass
bar with `tabBarMinimizeBehavior(.onScrollDown)`: Pulse, Longevity and Track
share the capsule, and Ask is a `Tab` with the `.prominent` role, which detaches
it into a disc at the trailing edge. On a regular width and on macOS the same
tabs become the system sidebar, from `TabView(.sidebarAdaptable)`.

The disc's glyph is the custom symbol `soma.mark` in the asset catalog, drawn
from the same trace as `SomaMark` in the package. A tab item renders an image
and a title, never a view, which is why the mark exists twice. The three tab
glyphs, `soma.pulse`, `soma.longevity` and `soma.track`, are custom symbols too
and share one scale in their templates so their strokes match.

Every tab page carries the same top bar through `tabPageChrome`
(`Features/Shared/TabPageChrome.swift`): the account on the leading edge, the
page's parts in a `SomaSegmentedControl` in the middle, notifications on the
trailing edge. Each page names its parts as a `PageSection` enum, and
`AppRouter` keeps which one is showing (`pulseSection`, `longevitySection`,
`trackSection`). Changing tab sends every other tab back to its first part:
Today, Body, Journal.

Longevity reads through three lenses, Body, Mind and Environment, and holds one
stack for all of them on `AppRouter.longevityPath` as `LongevityRoute` values.
The Vault (every Health reading by type, its records, source and quality) opens
from the account sheet and pushes `VaultRoute` values on whatever stack hosts it.

`SomaMetrics` and `SomaTypography` each ship a `touch` scale and a `pointer`
scale; `.standard` resolves to the right one at compile time.

## Build, run, verify

From the repository root:

```bash
xcodebuild -project App/Prism.xcodeproj -scheme Prism \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
```

```bash
xcodebuild -project App/Prism.xcodeproj -scheme Prism -destination 'platform=macOS' build
```

```bash
xcodebuild -project App/Prism.xcodeproj -scheme Prism \
  -destination 'generic/platform=visionOS' build
```

```bash
xcodebuild test -project App/Prism.xcodeproj -scheme Prism \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:PrismTests -parallel-testing-enabled NO
```

The packages test on their own, and they are faster:

```bash
cd Packages/SomaUI && swift test
```

```bash
cd Packages/WellnessKit && swift test
```

Add `CODE_SIGNING_ALLOWED=NO` to a build that has no signing team. All three
platforms build and every suite passes before anything is called done. A change
to a package is not verified by the package alone: build the app against it too.

## Things that will bite

- `App/Prism/` is a `PBXFileSystemSynchronizedRootGroup`. A new `.swift` file in
  it joins the target automatically, with no project edit. A file that must not
  compile does not belong under `App/Prism/`.
- The project sits in `App/`, so its local packages are `../Packages/SomaUI` and
  `../Packages/WellnessKit`. Moving the project breaks those references.
- `App/Config/Prism.xcconfig` includes `Cloud.xcconfig`, then the git ignored
  `Signing.xcconfig` and `Supabase.xcconfig`. Never commit either of the last
  two; the build workflow fails if one is in the tree.
- The app group `group.Soma.Prism` is written in three places: both
  entitlements files that carry it and `SnapshotStore.appGroup` in
  `App/SomaWidgetKit`. Change all three together.
- HealthKit returns nothing in the Simulator. The permission sheet appears and
  the queries run, but the store is empty, so every value renders as a dash. Real
  numbers need a device, or, in a Debug build on the Simulator, the Health
  seeder in `Features/Dev`, which writes a month of invented samples.
- Health's launch sheet covers the app on a simulator that has never answered
  it, and on iOS 27 XCUITest cannot reach it: the sheet belongs to
  `com.apple.HealthPrivacyService`, which shows XCUITest no buttons and does
  not swipe away. A UI test that taps anything launches the app with
  `-health.empty YES`, which swaps Apple Health for `EmptyHealthSource`:
  nothing is asked, nothing is read, and every value is a dash.
- HealthKit identifiers are not always the Swift member name with a capital
  first letter: Apple keeps acronyms in caps (`VO2Max`, `UVExposure`). Getting
  one wrong resolves the type to `nil` and the metric silently never appears.
  `HealthMetricCatalogTests` guards the two known cases.
- `SomaUIPreviewSupport` and `SomaPreviewSamples` are development only. If one
  turns up in a shipping view, that is the bug.
