# Is there an open source alternative to Bevel?

Yes. Prism is a free, open source (AGPL-3.0) health app for iPhone, iPad, Mac and Vision Pro that, like Bevel, works out sleep, recovery, strain, stress and energy scores from Apple Health. The difference is in the model around it: Prism has no paid tier, needs no account, computes every score on the device, and publishes the formulas in this repository.

## Side by side

Bevel facts below come from [docs/COMPARISON.md](../COMPARISON.md), checked on 2026-10-18, where each cell links its source. Apps change, so check Bevel's own pages before you decide.

| | Prism | Bevel |
|---|---|---|
| Source code | Open, AGPL-3.0 | No source or open license found |
| Price (USD) | Free | Free tier, Pro $14.99 a month or $99.99 a year |
| Account | Not required ("Not now" on the first screen) | In practice yes |
| Sleep, recovery, strain, stress, energy | All five | All five |
| Where Apple Health data stays | On the device until you sign in | On the device while Bevel Intelligence is off |
| AI assistant | Ask, needs a cloud account, off in the build as shipped | Bevel Intelligence, Pro |
| Blood test import | Photo, PDF or typed, read on the device, free | Pro only |
| Mac and Vision Pro | Both build from the same target | Mac as an iPhone app only, Vision Pro not mentioned |
| Raw data export | ZIP of JSON and NDJSON, in the app | By email request |

## Where Bevel is ahead

- Bevel has an Apple Watch app. Prism has none in this build.
- Bevel connects directly to Garmin and Oura. Prism's direct Oura, Whoop and Withings sign in is written but switched off; it reads those brands through Apple Health.
- Bevel's assistant runs for you. Prism's Ask needs a cloud account and a backend key, which the public build doesn't ship.
- Bevel has a longer track record and a support team.

## Why the scores won't match

Both apps read the same Apple Health data, but the formulas differ. Prism's are public: see [how the sleep score works](how-the-sleep-score-works.md), [how the recovery score works](how-the-recovery-score-works.md) and [how strain, stress and energy work](how-strain-stress-and-energy-work.md). Compare trends within one app rather than numbers across two.

## Try Prism

Join the [TestFlight public beta](https://testflight.apple.com/join/15Bvq8Dr), or [build it from source](build-from-source-with-xcode.md).

## Related

- [Open source Oura app alternative](open-source-oura-app-alternative.md)
- [Prism, Athlytic, Gentler Streak and Welltory](prism-vs-athlytic-gentler-streak-welltory.md)
- [Full sourced comparison](../COMPARISON.md)
- [README](../../README.md)
