# Does Prism run on Mac and Apple Vision Pro?

Yes, from source. Prism is one SwiftUI app target that builds for iPhone, iPad, Mac (macOS 27) and Apple Vision Pro (visionOS 27), with `SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx xros xrsimulator` and device families 1, 2 and 7. Both builds compile, but Apple Health data on Mac and Vision Pro hasn't been checked by hand yet. The TestFlight public beta is for iPhone and iPad.

## How it looks there

- **Mac and iPad.** The same `TabView` becomes the system sidebar (`TabView(.sidebarAdaptable)`), with Pulse, Longevity, Track and Ask as sidebar items.
- **Vision Pro.** visionOS has no Liquid Glass, so every glass surface goes through SomaUI's `somaGlass(_:in:)`, which draws the regular material there and the system glass on iOS and macOS. `GlassGuardTests` fails on a direct `glassEffect` call, because one would break only the headset build.
- **Widgets** are an iOS extension and aren't built for Mac or Vision Pro.
- **Export** opens a save panel on a Mac instead of the share sheet.

## Build for Mac

```bash
xcodebuild -project App/Prism.xcodeproj -scheme Prism -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

To run it, set a team and bundle id in `App/Config/Signing.xcconfig`, change the app group, and turn on HealthKit for your team and app id. See [build from source](build-from-source-with-xcode.md).

## Build for Vision Pro

```bash
xcodebuild -project App/Prism.xcodeproj -scheme Prism -destination 'generic/platform=visionOS' build CODE_SIGNING_ALLOWED=NO
```

The visionOS simulator runs the app with no signing setup. Apple Health is empty there, as on any simulator.

## What isn't there

- No Apple Watch app in this build.
- No web version.
- An Android version is in development. See [ROADMAP.md](../../ROADMAP.md).

## Related

- [Build Prism from source with Xcode](build-from-source-with-xcode.md)
- [Widgets and Control Center](widgets-and-control-center.md)
- [docs/ARCHITECTURE.md](../ARCHITECTURE.md)
- [README](../../README.md)
