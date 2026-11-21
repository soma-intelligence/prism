# How do I use Oura, Whoop, Garmin or Apple Watch data in Prism?

Prism reads wearables through Apple Health. Turn on Apple Health writing in your device's own app (Oura, Whoop, Garmin Connect, Withings and others), allow Prism's Apple Health request, and Prism scores whatever arrived there alongside Apple Watch and iPhone data. Direct Oura, Whoop and Withings sign in is written in the code but switched off in this build.

## Steps

1. In your device's app, turn on its Apple Health connection and let it write sleep, heart rate, HRV, resting heart rate, workouts and activity.
2. Open Prism. Apple Health asks once, for every type Prism reads. Sensitive types start switched off; turn on what you want scored.
3. Check what arrived: open the Vault from the account button. It lists every reading by type with its source.
4. Scores appear after seven recorded nights (sleep, recovery) and seven days of heart readings (stress).

To change access later: Health app, your picture, Apps, Prism.

## Sources the app lists

Settings, Health access lists these (`App/Prism/Core/Providers/DataProvider.swift`):

| Source | How Prism gets it in this build |
|---|---|
| Apple Health, Apple Watch | Directly |
| iPhone motion | Directly, from Motion & Fitness |
| Oura, Whoop, Withings | Through Apple Health. Direct sign in written, shown as "Soon" |
| Garmin, Polar, Ultrahuman, Eight Sleep, Dexcom, Strava, MyFitnessPal | Through Apple Health |
| Fitbit, Levels | "Soon" |

What each brand writes to Apple Health is decided by that brand's app, not by Prism. If a metric doesn't show in the Vault, it isn't in Apple Health.

## Several devices at once

Apple Health keeps each sample with its source and device. Prism merges overlapping sleep into sessions (`SleepSessionizer.swift`) and keeps the source on each reading, so the Vault shows where a number came from.

## Why the direct connections are off

The OAuth flows are in `App/Prism/Core/Providers`, but `ProviderConfig.clientIDs` is empty: turning them on means registering Prism with each service. Until then Apple Health is the route. See [ROADMAP.md](../../ROADMAP.md).

## No wearable at all

Prism still runs. Steps, distance and floors come from the iPhone, and strain can score from them. Sleep, recovery and stress need a device that writes sleep and heart data.

## Related

- [Open source Oura app alternative](open-source-oura-app-alternative.md)
- [An open source Apple Health dashboard](open-source-apple-health-dashboard.md)
- [How the recovery score works](how-the-recovery-score-works.md)
- [README](../../README.md)
