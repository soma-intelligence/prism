# What widgets and Control Center buttons does Prism have?

Prism ships five Home Screen and Lock Screen widgets (Scores, Vitals, Strain, Fuel and Log), two Control Center buttons that log a glass of water or a cup of coffee, and Live Activities. They live in the `SomaWidgets` extension (iOS) and read a snapshot of today's scores that the app shares through its app group on the device, so no widget needs a network.

## Widgets

From `App/SomaWidgets`:

| Widget | Shows | Sizes |
|---|---|---|
| Scores | Sleep, recovery or strain (you pick which) | Small, medium, Lock Screen circular and rectangular |
| Vitals | Resting heart rate, HRV and sleep | Small, medium, large, Lock Screen rectangular and inline |
| Strain | Energy since bedtime and stress today | Medium, large |
| Fuel | Burned and eaten today | Small, medium |
| Log | Water and coffee in one tap, mood and meals in the app | Small, medium, large, Lock Screen circular |

## Control Center

| Control | Action |
|---|---|
| Log water | Adds a glass of water to today |
| Log coffee | Adds a cup of coffee to today |

Both run `LogDrinkIntent` without opening the app.

## Live Activities

One Live Activity type covers wind down, nap, cardio test and meeting, on the Lock Screen and in the Dynamic Island (`SomaLiveActivity.swift`).

## How the data gets there

The app writes a snapshot of today's scores to the shared app group `group.Soma.Prism` (`SnapshotStore` in `App/SomaWidgetKit`). The widgets read it. It stays on the device. If you build your own copy, change the app group in all three places listed in [build from source](build-from-source-with-xcode.md), or the widgets will be empty.

## Related

- [Prism on Mac and Vision Pro](prism-on-mac-and-vision-pro.md)
- [How strain, stress and energy work](how-strain-stress-and-energy-work.md)
- [README](../../README.md)
