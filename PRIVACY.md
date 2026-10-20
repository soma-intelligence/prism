# Privacy in Prism

This page describes what the code in this repository does with your data. It covers the app as built from this source. Paths are relative to the repository root, so you can check every statement.

Prism has two modes. Local mode needs no account. Cloud mode starts when you sign in to a Supabase project: Soma's, or your own if you self host.

## How the build is configured

`App/Config/Cloud.xcconfig` holds two values: the address of Soma's Supabase project and its publishable key. The address is set. The key is empty in this repository, so a build made from it has no backend: sign in, sync, Ask's model answers and the online article and news feed are off, and Explore reads only the article library bundled in the app (`App/Prism/Core/Account/SupabaseSettings.swift`, `App/Prism/Core/Articles/ArticleSources.swift`).

A publishable key is public by design. Row level security on the server decides what it can read, and the server's secret keys never go in the app.

## Local mode

Tap "Not now" on the first onboarding screen (`App/Prism/Features/Onboarding/OnboardingSignIn.swift`).

What stays on the device:

- What Prism reads from Apple Health. Apple Health asks once, for every type the app reads and writes, and the sensitive types start switched off.
- Your scores, worked out on the device (`Packages/WellnessKit/Sources/HealthScoring`).
- Your journal, check-ins, logs, mood entries and lab results, kept in the app's own storage.
- Your rituals and the days you ticked them (`App/Prism/Core/Track/TrackRitualStore.swift`), the order of your quick add tiles (`TrackQuickAddLayout` in `App/Prism/Features/Track/Log/TrackQuickAdd.swift`), the notes you write with a mood (`App/Prism/Core/Mind/MindStore.swift`), and Explore's interest log: the pages you open, the pieces you read and the ones you save, which Explore reads to order its shelves (`App/Prism/Core/Articles/ExploreInterest.swift`). Cloud sync doesn't send these, and they aren't in the data export yet.
- Blood test photos and PDFs. They're read on the device with Apple's text recognition (`App/Prism/Core/Lab/BloodReportReader.swift`) and aren't uploaded.
- A snapshot of today's scores, shared with the widgets through the app group on the device.
- The last numbers each Longevity lens showed (Body, Mind and Environment), so the tab opens on them after a relaunch while it reads Apple Health again (`App/Prism/Features/Longevity/LongevitySnapshot.swift`). It's one small file in the app's own storage, protected while the phone is locked. It holds what the lenses draw: the values and their words, thirty days of each reading's line, today's stress line, fourteen days of mood, the weather and the rounded place it was asked for, and your sleep places with the spots you set for them, as `SleepPlaceStore.swift` keeps them. It never holds the device's own position. It's written under who is signed in (a hash of the account id), and dropped when someone else signs in, when you sign out, by "Delete my data", and, for the Mind lens, when you delete what Mind keeps. Cloud sync doesn't send it, and it isn't in the data export.

What leaves the device:

- **Weather and air quality.** The Environment card asks [Open-Meteo](https://open-meteo.com) for the forecast and air quality at your location, rounded to 0.1 degree of latitude and longitude, about 11 km (`App/Prism/Features/Longevity/Environment/EnvironmentWeather.swift`). The location is your device's while the app is in use, if you allowed it, or the city you picked on the Weather page (`EnvironmentLocation.swift`). No account, key or identifier is sent with it. In the build as configured here, this is the only request carrying anything about you that goes to a service other than Apple's.
- **Place names, through Apple.** The device location, rounded to 0.01 degree (about 1 km), goes to Apple's MapKit reverse geocoding to name the place on the Environment card (`MKReverseGeocodingRequest` in `EnvironmentLocation.swift`). The name is then cached on the device. The map on the card draws the device's own position, unrounded, on the device, and a sleep place you set from where you are keeps that position on the device too (`SleepPlaceStore.swift`); only the name lookup and the weather request are rounded.
- **Workout place names, through Apple.** The Territory page groups this month's workout routes by place and names each group through the same Apple reverse geocoder (`TerritoryNames` in `App/Prism/Features/Longevity/Metrics/TerritoryPage.swift`). The point sent is the middle of the group, rounded to 0.01 degree (about 1 km) before it leaves the device, with the same rule as the Environment card (`App/Prism/Core/Location/CoarseCoordinate.swift`). The middle is the average of each route's average GPS fix, as Apple Health recorded them (`Territory.places` in `App/Prism/Core/Fitness/Territory.swift`). The map on the page draws your routes and Home at their exact positions on the device, and loads Apple Maps tiles for that area; only the name lookup is rounded.
- **City search, through Apple.** The city search on the Weather page, and the search for where you slept, send what you type to Apple's MapKit search (`MKLocalSearch` in `App/Prism/Features/Pulse/Scores/WeatherPage.swift`).
- **Maps, through Apple.** Map views load Apple Maps tiles for the area they show: your workout routes and Home on the Territory page (`App/Prism/Features/Longevity/Metrics/TerritoryPage.swift`), and the place card and your sleep places on the Environment lens (`App/Prism/Features/Longevity/Environment/EnvironmentPlaceCards.swift`). These maps are drawn around exact positions, not rounded ones: the place card is centred on the exact spot when the device gave its own position, and the sleep places map fits the exact spots you set. So the tiles Apple is asked for show a tighter area than the rounded name lookup, about 900 m across around the spot. All three use Apple's services under Apple's privacy terms.
- **The article and news feed, only when a key is set.** If the build has a publishable key (Soma's, or yours), Explore fetches published articles and news from that project with a plain GET and the key. No user id goes with it (`App/Prism/Core/Articles/ArticleSources.swift`, `App/Prism/Core/Articles/NewsItem.swift`). Without a key nothing is fetched.
- **Feed cover images, only when a key is set.** A feed row can carry an image address: `cover_image_url` on an article and `image_url` on a news item. The cover views load it with SwiftUI's `AsyncImage` (`Packages/SomaUI/Sources/SomaUI/Components/Readings/SomaArticleCover.swift`, used by `PulseExploreView.swift`, `PulseArticleReader.swift` and `ExploreNews.swift`), straight from whatever host the row names, not through Soma's project. For a news item that's the publisher's own site or its image host. Each load is one GET to that URL. It carries the image address, and, as any image load does, the device's IP address and the user agent of the system networking stack. Prism adds no account, key, user id or token. The host sees that a device at that address asked for that image, and can tell when. On Soma's project, the feed list in `supabase/functions/news-ingest/feeds.ts` sets `images` to true for the CDC feed only, so that is the one publisher whose images load there today. On a project you host, your own feed list decides, so any host you allow can see these requests. Without a key no row is fetched and no cover image is requested: Explore shows the bundled library and drawn covers.
- **Links you open.** Article sources, Terms, Privacy and Help open in a browser view when you tap them.

Prism has no analytics, advertising or crash reporting code. Settings, Data, Data and diagnostics has "Share crash reports" and "Share usage" switches; in this build they only store your choice, both start off, and nothing reads them to send anything (`App/Prism/Features/Settings/Pages/DataDiagnosticsPage.swift`, `App/Prism/Core/Global/GlobalSettings.swift`).

Ask still works in local mode, within limits: it answers its suggested questions from today's numbers on the device and says that other questions need the model (`App/Prism/Features/Ask/AskPage.swift`).

## Cloud mode

Cloud mode needs a key in the build and a sign in with Apple (`App/Prism/Core/Account/AccountSession.swift`). Sign in with Apple is the only sign in the app offers; email sign in is planned (see `ROADMAP.md`). While you're signed in, `App/Prism/Core/Cloud/CloudSync.swift` sends the project:

- your profile (first name, birth date, sex, height, units and the like) and its photo;
- your records: journal days, check-in answers, moods, mind check-ins, track logs, lab results, daily scores, the notification inbox and the list of linked services (never their tokens);
- your Apple Health samples and daily summaries, with each sample's source and device. Sensitive types, such as cycle tracking, stay on the device (`Packages/WellnessKit/Sources/HealthCloud/HealthSampleUploader.swift`). Health is read only after you've answered Apple Health's permission sheet;
- a record of this installation: platform, model and versions;
- your Ask conversations.

Every table has row level security: a signed in person reads and writes only their own rows. The schema is in `supabase/migrations`, and `supabase/README.md` lists every table and bucket.

**Ask with a model.** Your question, the conversation so far and a short summary of your numbers go to the `ask-soma` function (`App/Prism/Core/Ask/AskClient.swift`, `supabase/functions/ask-soma`). The summary holds today's scores, each metric's current value against its usual range and trend, your age and sex, and never raw samples (`App/Prism/Core/Ask/AskContextBuilder.swift`). The function forwards these to a chat model on Microsoft Azure, the deployment named by `AZURE_OPENAI_DEPLOYMENT`. It stores your question and the answer in `ask_messages`, and doesn't store the summary. Each person gets 60 messages an hour by default (`ASK_PER_HOUR`).

**Signing out** stops the sync. What's on the device stays there.

On Soma's project, Soma Labs, Inc. runs the servers. Its own privacy policy is at https://www.somalabs.me/legal/privacy. On a project you host, you do.

## Export your data

Settings, Data, Export my data. Prism builds one ZIP on the device (`App/Prism/Core/Cloud/DataExport.swift`) holding:

- `README.txt`, explaining each file;
- `profile.json`, and `profile.jpg` if you set a photo;
- one JSON file per record table (journal days, check-in answers, mood logs, mind check-ins, track logs, lab results, scores, notification inbox, provider connections and Ask conversations);
- `health/<identifier>.ndjson`, one file per Apple Health type, one sample a line with its source.

Rituals, the quick add order, mood notes and Explore's interest log aren't in the export yet: they stay on the device.

The share sheet opens on the file (a save panel on a Mac). It works in local mode. When you're signed in you can also keep a copy in your private storage on the project.

## Delete your data

**Signed in.** Settings, Data, Delete my data. After you confirm, the `delete-account` function removes your files from both storage buckets, then deletes your account, which deletes your rows in every table (`App/Prism/Core/Account/AccountDeletion.swift`, `supabase/functions/delete-account/index.ts`). The app then signs out and erases its local sync database. Data still on the device stays until you delete the app.

**Local mode.** Nothing is kept online for you. Deleting the app erases what's on the device.

Prism never deletes anything from Apple Health. To take back its access, open the Health app, tap your picture, then Apps.

## Questions

Open an issue for a question about this page. Report a privacy or security problem privately, as [SECURITY.md](SECURITY.md) describes.
