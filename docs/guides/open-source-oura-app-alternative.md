# Is there an open source alternative to the Oura app?

Prism is an open source (AGPL-3.0) app that can show scores from your Oura Ring's data without an Oura membership, as long as the Oura app writes that data to Apple Health. It doesn't replace the ring: Prism has no sensor and reads what Apple Health holds. It works out its own sleep, recovery, strain, stress and energy scores on the device, with formulas you can read in this repository.

## How Oura data reaches Prism

1. In the Oura app, turn on its Apple Health connection so it writes sleep, heart rate, HRV and activity there.
2. In Prism, allow Apple Health access when asked. Apple Health asks once, for every type the app reads.
3. Prism reads whatever Oura wrote, along with any other source, and scores it.

Prism also has a direct Oura sign in (`App/Prism/Core/Providers/DataProvider.swift`), written but switched off in this build: Settings, Health access shows it as "Soon". See [ROADMAP.md](../../ROADMAP.md).

## Side by side

Oura facts come from [docs/COMPARISON.md](../COMPARISON.md), checked on 2026-10-18, each cell sourced there.

| | Prism | Oura app |
|---|---|---|
| Source code | Open, AGPL-3.0 | Proprietary; a public web API for members |
| Price (USD) | Free | App free, membership $5.99 a month or $69.99 a year |
| Hardware | None of its own | An Oura Ring |
| Account | Not required | Required |
| Where data is held | On the device until you sign in | On Oura's servers |
| Scores | Sleep, recovery, strain, stress, energy | Sleep, Readiness, Activity, Daytime Stress |
| Platforms | iPhone, iPad, Mac, Vision Pro | iPhone, Apple Watch, Vision Pro, Android, web |
| Raw data export | ZIP of JSON and NDJSON | CSV, by request |

## Where the Oura app is ahead

- It's made by the company that makes the ring, so it reads every ring metric directly, including ones that may not reach Apple Health.
- It has Android and Apple Watch apps. Prism has neither yet (Android is in development).
- Oura Advisor runs for members. Prism's Ask needs a cloud account that the public build doesn't ship with.

## Why Prism's numbers differ from Oura's

Prism doesn't copy Oura's scores. It recomputes from the raw readings against your own baselines, so a Prism recovery and an Oura Readiness for the same night can differ. See [how the recovery score works](how-the-recovery-score-works.md).

## Related

- [Use Oura, Whoop, Garmin and Apple Watch data](use-oura-whoop-garmin-apple-watch-data.md)
- [Open source Bevel alternative](open-source-bevel-alternative.md)
- [Full sourced comparison](../COMPARISON.md)
- [README](../../README.md)
