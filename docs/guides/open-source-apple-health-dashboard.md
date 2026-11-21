# Is there an open source Apple Health dashboard app?

Prism is an open source (AGPL-3.0) Apple Health dashboard for iPhone, iPad, Mac and Vision Pro. It reads the Apple Health types it asks permission for, from a 192 entry metric catalog, shows every reading by type with its source in the Vault, and turns the data into daily sleep, recovery, strain, stress and energy scores on the device. It's free and needs no account.

## What you can see

| Where | What |
|---|---|
| Pulse, Today | The five daily scores, with Trends over time |
| Longevity, Body | Cardio, strength, muscle work and body measurements |
| Longevity, Mind | Mood, check-ins, breathing, and optionally your calendar against stress and HRV |
| Longevity, Environment | Weather, air quality and daylight where you are |
| Vault (from the account button) | Every Apple Health reading by type, with its records, source and quality |
| Widgets | Scores, vitals, strain, fuel and a quick log on the Home Screen |

## How it reads Apple Health

- **One permission sheet.** `HealthAccess` asks once for every type the app reads and writes. Sensitive types sit in that sheet switched off.
- **One catalog.** `Packages/WellnessKit/Sources/HealthExportCore/Catalog/HealthMetricCatalog.swift` lists 192 entries: 117 quantities, 66 categories, 2 correlations, workouts and the characteristics, each with a canonical unit.
- **One reader.** `HealthKitSampleSource` in `HealthExportHealthKit` reads behind the `HealthSampleSource` contract, so tests and the Simulator can swap in other sources.
- **iPhone motion.** Without a watch, steps, distance and floors come from the phone's Motion & Fitness data (`Core/Motion/PhoneMotion`).
- **A dash for no data.** A missing value shows as a dash, never a zero.

Prism never deletes anything from Apple Health.

## Reuse it in your own app

The Health reading and scoring live in a separate Swift package, `Packages/WellnessKit`, with products `HealthExportCore`, `HealthExportHealthKit` and `HealthScoring`. You can read them, test them with `swift test`, and build on them under the AGPL-3.0. See [docs/ARCHITECTURE.md](../ARCHITECTURE.md).

## Get it

Join the [TestFlight public beta](https://testflight.apple.com/join/15Bvq8Dr) or [build from source](build-from-source-with-xcode.md).

## Related

- [Use Oura, Whoop, Garmin and Apple Watch data](use-oura-whoop-garmin-apple-watch-data.md)
- [Export and delete your data](export-and-delete-your-data.md)
- [Prism on Mac and Vision Pro](prism-on-mac-and-vision-pro.md)
- [README](../../README.md)
