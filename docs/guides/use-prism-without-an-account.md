# Can I use Prism without an account, with my data only on my phone?

Yes. Tap "Not now" on the first onboarding screen and Prism runs in local mode: what it reads from Apple Health, your scores, journal, logs and lab results stay on the device. In the build as shipped, the only request carrying anything about you to a service other than Apple's is the weather and air quality card, which sends a location rounded to 0.1 degree (about 11 km) to Open-Meteo.

This page summarizes [PRIVACY.md](../../PRIVACY.md). That page is the reference, with a source path for every statement.

## What stays on the device

- What Prism reads from Apple Health.
- Your scores, worked out on the device by `HealthScoring`.
- Journal, check-ins, logs, moods and lab results.
- Blood test photos and PDFs, read with Apple's text recognition on the device.
- Your sleep places and the Longevity snapshot.
- A snapshot of today's scores, shared with the widgets through the app group.

## What still uses the network in local mode

| Request | Sent | To |
|---|---|---|
| Weather and air quality | Location rounded to 0.1 degree (about 11 km), no identifier | Open-Meteo |
| Place names | Location rounded to 0.01 degree (about 1 km) | Apple MapKit |
| Workout place names | Middle of each group of routes, rounded to 0.01 degree | Apple MapKit |
| City search | What you type | Apple MapKit |
| Maps | Tile requests for the area shown | Apple Maps |
| Links you open | The page | Its site |

## What isn't in the app

No analytics, advertising or crash reporting code. The "Share crash reports" and "Share usage" switches only store your choice and start off.

## Why the build has no backend

`App/Config/Cloud.xcconfig` ships with an empty publishable key, so sign in, sync, Ask's model answers and the online article feed are off in a build from this repository. Explore reads the bundled article library. To add a backend, run your own: see [docs/SELF_HOSTING.md](../SELF_HOSTING.md).

## Erase local data

Settings, Data, Erase data on this iPhone removes the journal, track logs, Mind data, sleep places, rituals, Explore's interest log and the Longevity snapshot. Apple Health is untouched. See [export and delete your data](export-and-delete-your-data.md).

## Related

- [Export and delete your data](export-and-delete-your-data.md)
- [PRIVACY.md](../../PRIVACY.md)
- [Self hosting](../SELF_HOSTING.md)
- [README](../../README.md)
