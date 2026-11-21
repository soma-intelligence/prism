# How do I build Prism from source with Xcode?

Clone the repository, open `App/Prism.xcodeproj` in Xcode 27 and run the `Prism` scheme on an iOS or visionOS simulator. That needs no account, no signing team and no setup: the build runs in local mode. To run on your own iPhone or a Mac, copy `App/Config/Signing.example.xcconfig` to `App/Config/Signing.xcconfig` and set your team id, a bundle id and your own app group.

## Requirements

- A Mac with Xcode 27 (Swift 6 toolchain).
- Targets: iOS 27, iPadOS 27, macOS 27, visionOS 27.

## Run in the Simulator

```bash
git clone https://github.com/soma-intelligence/prism.git
cd prism && open App/Prism.xcodeproj
```

Pick the `Prism` scheme and an iPhone or Vision Pro simulator, then Run. Apple Health is empty in the Simulator, so values show as a dash. In a Debug build, the Health seeder in `App/Prism/Features/Dev` writes a month of invented samples so the pages have numbers.

## Run on a device or a Mac

1. Copy the signing template (the copy is git ignored; never commit it):

   ```bash
   cp App/Config/Signing.example.xcconfig App/Config/Signing.xcconfig
   ```

2. Set `PRISM_DEVELOPMENT_TEAM` to your ten character team id and `PRISM_BUNDLE_ID` to an id unique to you, such as `com.yourname.Prism`. The widget extension takes the same id with `.SomaWidgets` added.
3. Change the app group `group.Soma.Prism` to one you own, in all three places: `App/Prism.entitlements`, `App/SomaWidgets/SomaWidgets.entitlements` and `SnapshotStore.appGroup` in `App/SomaWidgetKit`.
4. On a Mac, turn on the HealthKit capability for your team and app id.

A free Personal Team should be enough to run on your own device, but the maintainers haven't tried it.

## Build from the command line

`CODE_SIGNING_ALLOWED=NO` lets the Mac and device builds compile without a team:

```bash
xcodebuild -project App/Prism.xcodeproj -scheme Prism \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project App/Prism.xcodeproj -scheme Prism \
  -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project App/Prism.xcodeproj -scheme Prism \
  -destination 'generic/platform=visionOS' build CODE_SIGNING_ALLOWED=NO
```

Use any iPhone simulator you have installed in place of `iPhone 18 Pro`.

## Run the tests

```bash
xcodebuild test -project App/Prism.xcodeproj -scheme Prism \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:PrismTests -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
(cd Packages/SomaUI && swift test)
(cd Packages/WellnessKit && swift test)
(cd App/SomaWidgetKit && swift test)
```

## Common problems

| Symptom | Cause |
|---|---|
| Every value is a dash | Apple Health is empty in the Simulator. Use the Health seeder or a device |
| Mac build stops on a missing development certificate | No team set. Add `Signing.xcconfig` or `CODE_SIGNING_ALLOWED=NO` |
| Signing can't register the app group | `group.Soma.Prism` belongs to Soma. Change it in all three places |
| A new `.swift` file breaks the build | Anything under `App/Prism/` joins the target automatically |
| Sign in and Ask do nothing | `Cloud.xcconfig` ships with an empty key. See [self hosting](../SELF_HOSTING.md) |

## Related

- [Prism on Mac and Vision Pro](prism-on-mac-and-vision-pro.md)
- [Contribute and sign the CLA](contribute-and-sign-the-cla.md)
- [CONTRIBUTING.md](../../CONTRIBUTING.md), [AGENTS.md](../../AGENTS.md)
- [README](../../README.md)
