# How does Prism compare with Athlytic, Gentler Streak and Welltory?

All four read Apple Health on iPhone, but Prism is the only one of them that's open source and has no paid tier. Athlytic, Gentler Streak and Welltory are proprietary apps that are free to download and sell a subscription for their full feature set. Prism is AGPL-3.0, free, needs no account, and builds for iPhone, iPad, Mac and Vision Pro.

## The table

As of November 2026, read from each app's App Store listing. Prices change and vary by country, so they're left out: check the listing in your region.

| | Prism | Athlytic | Gentler Streak | Welltory |
|---|---|---|---|---|
| Source code | Open source, AGPL-3.0 | Not published | Not published | Not published |
| Price model | Free, no purchases | Free download, Athlytic Pro subscription | Free, Premium subscription | Free download, Pro subscription |
| Platforms named on the listings read | iPhone, iPad, Mac, Vision Pro | iPhone, Apple Watch | iPhone, iPad, Apple Watch | iPhone, Android |
| Apple Watch app | No | Yes | Yes | Not checked |
| Reads Apple Health | Yes | Yes | Yes | Yes |

Listings read: [Athlytic](https://apps.apple.com/us/app/athlytic-ai-fitness-coach/id1543571755), [Gentler Streak](https://apps.apple.com/us/app/gentler-streak/id1576857102), [Welltory](https://apps.apple.com/app/id1074367771).

## What Prism has in common with each

- **Athlytic** is known for a recovery score from HRV and resting heart rate from an Apple Watch. Prism does too, against 60 day personal baselines: see [how the recovery score works](how-the-recovery-score-works.md).
- **Gentler Streak** focuses on activity and rest. Prism's strain score and its daily target band, which follows your recovery, cover similar ground: see [strain, stress and energy](how-strain-stress-and-energy-work.md).
- **Welltory** focuses on stress and energy. Prism has a daily stress reading from HRV and resting heart rate, and an energy bank that charges overnight and drains through the day.

## What's different about Prism

- The formulas are public, in `Packages/WellnessKit/Sources/HealthScoring`, so you can read why a score is what it is.
- No account and no analytics code. In local mode your data stays on the device. See [use Prism without an account](use-prism-without-an-account.md).
- It runs on Mac and Vision Pro from the same target.
- It also has a journal, a track log, blood panel reading and fifteen planning tools.

## Where Prism falls short

No Apple Watch app in this build, no Android release yet, and it's a new project. Its scores are only as good as what your devices write to Apple Health.

## Related

- [Open source Bevel alternative](open-source-bevel-alternative.md)
- [Open source Oura app alternative](open-source-oura-app-alternative.md)
- [Full sourced comparison with Apple Health, Oura and Bevel](../COMPARISON.md)
- [README](../../README.md)
