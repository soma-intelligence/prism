# Prism compared with Apple Health, the Oura app and Bevel

Checked on 2026-10-18.

Prism is an open source health app for iPhone, iPad, Mac and Vision Pro. It reads your data from Apple Health, calculates sleep, recovery, strain, stress and energy scores on the device, and keeps a journal and a track log. This page sets it next to three apps people use for the same job. It is meant to be fair: where another app is ahead, the table says so.

Two things to read first:

- Prism has no sensor of its own. It scores what Apple Health already holds, so its numbers are only as good as the watch, ring or phone that wrote them.
- Prism is new and has no clinical validation. Its scores are for your own trends and are not medical advice. Nothing here claims to diagnose or treat anything.

Every competitor cell carries a note with the page it rests on, including the cells that say a feature is missing: for those, the note names the page that was read and found silent.

Competitor cells come from each company's own site, help centre, privacy policy or App Store listing, linked in the notes. Where only a press report or a user board was found, the cell says so, and where nothing could be confirmed it says "unconfirmed". Apps change: check the linked page before you decide.

## The table

| | Prism | Apple Health | Oura app | Bevel |
|---|---|---|---|---|
| Price (USD) | Free. $0 per month, $0 per year | Free, built in. No paid Health plan exists today [^a1] | App free to download. Membership $5.99 per month or $69.99 per year [^o1] | Free tier. Pro $14.99 per month or $99.99 per year [^b1] |
| Hardware required | None to install. Scores need data in Apple Health, from a watch, ring or the phone's own motion sensors | None for the basic app. Apple Watch needed for sleep score, vitals and Training Load [^a2] | An Oura Ring, plus a membership for most features [^o1] | None of its own. Reads Apple Health or a connected wearable. Whether the iPhone alone is enough: unconfirmed [^b2] |
| Open source | Yes, AGPL-3.0 | No. No source or open license published [^a9] | No. Proprietary app, a public web API only [^o11] | No. No source or open license found [^b9] |
| Account required | No. "Not now" on the first onboarding screen | No. iCloud is optional [^a3] | Yes [^o2] | In practice yes (sign in by email in its policy). A strict statement: unconfirmed [^b3] |
| Works offline | Scores, journal, track log and blood panel reading work with no connection. Four things use the network: the weather and air quality card, the article and news feed (when a Soma backend key is set), account sync, and Ask [^p1] | Yes, data is stored on the device. The word "offline" is not on Apple's page, this is inferred [^a3] | Partly. The ring stores data until it syncs. Scores come after sync with Oura's servers [^o3] | Unconfirmed. Its pricing help page and privacy policy do not address it [^b1][^b3] |
| Data stays on device by default | Your health data, journal, scores and labs stay on the device until you sign in to a cloud project. Without an account, as built today without a Soma key, the only request carrying user related data to a service other than Apple's is the weather card: a location rounded to 0.1 degree (about 11 km) goes to Open-Meteo. Apple's MapKit gets the location rounded to 0.01 degree (about 1 km) to name the place, the middle of each group of this month's workout routes, rounded the same way, to name it on the Territory page, the Weather page's city search, and the map views' tile requests. If Soma's key is set, the article and news feed are also fetched anonymously from the Soma project, with no user id [^p1] | Yes, with iCloud sync on by default when iCloud is on [^a3] | No. Measured and calculated data is held on Oura servers [^o3] | Apple Health data stays on the device while Bevel Intelligence is off. Data from connected brands is stored on its servers [^b3] |
| Sleep score | Yes | Yes, with Apple Watch [^a2] | Yes (daily Sleep Score) [^o1] | Yes [^b4] |
| Recovery or readiness score | Yes (recovery) | Announced for Apple Watch Series 12 and Ultra 4. The redesigned Health app is planned for late 2026, not shipped. No single score in the shipped app (unconfirmed) [^a4] | Yes (Readiness) [^o1] | Yes (Recovery) [^b4] |
| Strain or activity load | Yes (strain) | Training Load with an effort rating, with Apple Watch [^a5] | Activity Score and activity goals. No strain number found [^o4] | Yes (Strain, and Muscular Load) [^b4] |
| Stress | Yes | No stress score. Mood logging only (State of Mind) [^a2] | Yes (Daytime Stress, Resilience) [^o4] | Yes (Stress Score, 0 to 100) [^b4] |
| Energy | Yes (morning and end of day energy) | None found on the page checked [^a2] | None found on the pages checked. Unconfirmed [^o4] | Yes (Energy Bank) [^b4] |
| Journal or habit tracking | Yes. Journal, check-ins and a track log (food, water, supplements, caffeine, fasting, mood, practices) | Partial. State of Mind logging and the separate Journal app [^a2] | Yes (Tags and notes) [^o5] | Yes (Journal, free) [^b1] |
| Blood test import | Yes. Photo, PDF or typed values, read on the device, every value checked by you before saving | Health Records import from some US providers. Lab upload announced, not shipped [^a6] | Yes. $99 Quest panel (US, members) and PDF Lab Uploads, rollout dated 2026-06-30, live status unconfirmed [^o6] | Yes, Pro only (Health Records, file or photo) [^b5] |
| AI assistant | Ask is built, but off in the public build as configured today. It needs a Soma cloud account, and the build ships without the cloud key, so accounts and Ask stay off until a key is set (a self hoster can point it at their own Supabase project and model deployment). 60 messages an hour by default [^p2] | No chat. Announced Apple Intelligence summaries, not shipped [^a6] | Yes (Oura Advisor, in membership) [^o7] | Yes (Bevel Intelligence, Pro, with a weekly allowance) [^b6] |
| Third party data (Oura, Whoop, Withings) | Reads the Apple Health metrics it asks permission for (192 entry catalog), which includes what other apps write there. Direct Oura, Whoop and Withings sign-in is written but switched off in this build [^p3] | Reads what other apps write to Apple Health. Apple lists no vendors [^a10] | Reads Apple Health, Health Connect, Dexcom Stelo, Strava. Whoop and Withings not listed [^o8] | Apple Health, Garmin, Oura (needs an Oura subscription), Google Health. Whoop not possible, Withings not built [^b7] |
| Platforms: iPhone | Yes | Yes [^a7] | Yes [^o9] | Yes [^b8] |
| Platforms: Mac | Yes (builds for macOS) | No Health app [^a7] | No (not listed on its App Store page) [^o9] | Runs as an iPhone app only [^b8] |
| Platforms: Vision Pro | Yes (builds for visionOS) | Mindfulness only [^a7] | Yes (listed) [^o9] | Not mentioned on its App Store page [^b8] |
| Platforms: Android | No | No. Apple lists none [^a7] | Yes [^o9] | No [^b8] |
| Platforms: web | No | No. Apple lists none [^a7] | A web app exists, its future unconfirmed [^o9] | No [^b8] |
| Export of raw data | Yes. One ZIP of JSON files, plus one NDJSON file per Apple Health metric | Yes. XML [^a8] | Yes. CSV, by request, without membership [^o10] | No self serve export found. Copy by email request [^b3] |

## Where Prism falls short

- No sensor of its own. An Oura Ring or an Apple Watch measures the body. Prism only reads what such devices write to Apple Health.
- No Android and no web version. Oura has an Android app and a web app (the web app's future is unconfirmed) [^o9].
- No Apple Watch app in the public build. Apple Health, Oura and Bevel all list one [^a2][^o9][^b8].
- No clinical validation. Apple lists watch features such as an ECG app and sleep apnea notifications [^a2]. Prism has no such features and makes no such claims.
- A new project. Oura, Apple and Bevel have years of user feedback, support teams and large user bases. Prism has none of that yet.
- Ask needs a Soma cloud account, and the public build as configured today ships without the cloud key, so accounts and Ask are off until a key is set. Bevel and Oura run their assistants for you. A self hoster deploys `supabase/functions/ask-soma`, brings a model, and points the build at their own Supabase project.
- Direct sign in to Oura, Whoop and Withings is not switched on in the public build. Reading those brands through Apple Health works today where the brand writes to Apple Health.
- The weather card sends a rounded location (about 11 km) to a third party, Open-Meteo. As built today without a Soma key it is the only request carrying user related data to a service other than Apple's (Apple's MapKit names the place from a location rounded to 0.01 degree, about 1 km, names workout places from the middle of each group of routes rounded the same way, runs the city search and serves the map tiles). With Soma's key set, the article and news feed are also fetched, anonymously, from the Soma project, and their cover images load straight from the publisher's host (the CDC's, as the feed list stands), which sees the device's IP address and user agent.
- Mac and Vision Pro builds exist, but Apple Health data on those platforms has not been checked by hand for this page.

## Where Prism is ahead

- Price: free, no membership, no paid tier. Oura needs a ring and a membership, and Bevel keeps its AI coach and records behind Pro.
- Open source: the code, the scoring and the backend are public under AGPL-3.0, so you can read how every score is made.
- No account needed. Health data, journal, scores and labs stay on the device until you choose to sign in. As built today without a Soma key, the only request carrying user related data to a service other than Apple's is the rounded location for the weather card. With Soma's key set, the article and news feed are also fetched anonymously, and their cover images load from the publisher's host.
- Blood panel reading happens on the device, with no upload and no paid tier.

## How the Prism column was checked

Each Prism cell was read from the code, not from memory. Paths are relative to the root of the public repository.

| Cell | Proof |
|---|---|
| Price free | No purchase code anywhere in `App/Prism` or `Packages` (no StoreKit use) |
| Open source, AGPL-3.0 | The `LICENSE` file at the repository root |
| Account not required | `App/Prism/Features/Onboarding/OnboardingSignIn.swift` ("Not now"), `App/Prism/Core/Account/SupabaseSettings.swift` (without a project there is no account and everything stays on the phone) |
| Works offline, data on device | `App/Prism/PrismApp.swift` (SwiftData container), `App/Prism/Core/Cloud/CloudSync.swift` (health and record uploads run only while someone is signed in) |
| Network without an account | `App/Prism/Features/Longevity/Environment/EnvironmentWeather.swift` (`api.open-meteo.com` and `air-quality-api.open-meteo.com`, latitude and longitude rounded to 0.1 degree), `App/Prism/Features/Longevity/Environment/EnvironmentLocation.swift` (when in use location, else the city picked on the Weather page; place name from Apple's `MKReverseGeocodingRequest` on the location rounded to 0.01 degree), `App/Prism/Features/Pulse/Scores/WeatherPage.swift` (city search through Apple's `MKLocalSearch`), `App/Prism/Features/Longevity/Metrics/TerritoryPage.swift` (`TerritoryNames`: `MKReverseGeocodingRequest` on `Territory.Place.center`, the mean of the routes' mean GPS fixes from `App/Prism/Core/Fitness/Territory.swift`, rounded to 0.01 degree by `App/Prism/Core/Location/CoarseCoordinate.swift` before the request; also an Apple Maps view), `EnvironmentPlaceCards.swift` (Apple Maps views), `App/Prism/Core/Articles/ArticleSources.swift` and `NewsItem.swift` (GET to the Soma project with the publishable key, no user id; without the key the bundled library is read) |
| Sleep, recovery, strain, stress and energy | `Packages/WellnessKit/Sources/HealthScoring` (`SomaScoringEngine.swift`, `StressEngine.swift`, `ScoringTypes.swift`) and `App/Prism/Core/Scoring` |
| Journal and tracking | `App/Prism/Core/Journal`, `App/Prism/Core/Track`, `App/Prism/Features/Track`, `App/Prism/Core/Journal/EffectMath.swift` |
| Blood test import | `App/Prism/Core/Lab/BloodReportReader.swift` (PDF text layer or Vision OCR, photographed page), `App/Prism/Features/Longevity/Lab/AddBloodTestSheet.swift` (photo, PDF, typed values, confirm screen) |
| AI assistant | `App/Prism/Core/Ask/AskClient.swift` (signed out is an error), `App/Config/Cloud.xcconfig` (`SOMA_SUPABASE_PUBLISHABLE_KEY` is empty, so there is no account), `App/Prism/Core/Account/SupabaseSettings.swift`, `supabase/functions/ask-soma/index.ts` (60 messages an hour by default, `ASK_PER_HOUR`; model deployment set by `AZURE_OPENAI_DEPLOYMENT`) |
| Third party data | `Packages/WellnessKit/Sources/HealthExportCore/Catalog/HealthMetricCatalog.swift` (192 entries: 117 quantities, 66 categories, 2 correlations, the workout and the characteristics; sensitive ones are asked only when opened), `App/Prism/Core/Providers/DataProvider.swift` (Oura, Whoop and Withings sign-in written; `ProviderConfig.clientIDs` is empty, so the button reads "Soon" in `App/Prism/Features/Settings/Pages/HealthAccessPage.swift`; Garmin, Polar and others come through Apple Health) |
| Platforms | `App/Prism.xcodeproj/project.pbxproj` (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx xros xrsimulator`, device family 1,2,7 for the app; no watch target); widgets in `App/SomaWidgets` (iOS) |
| Raw data export | `App/Prism/Core/Cloud/DataExport.swift` (ZIP with one JSON file per table and `health/<identifier>.ndjson`), `App/Prism/Features/Settings/Pages/ExportDataPage.swift` |

## Notes and sources

Read on 2026-10-18.

[^a1]: Apple, Health and fitness newsroom post, September 2026: https://www.apple.com/newsroom/2026/09/apple-advances-health-and-fitness-capabilities-using-apple-intelligence/ . The only health charge it names is a $119 lab panel, part of the redesign that is not shipped. Press reported that a paid Health plan was scaled back: https://www.mactrast.com/2026/02/apple-reportedly-scaling-back-plans-for-apple-health-in-ios-27/
[^a2]: Apple, Health: https://www.apple.com/ios/health/ . Sleep score, vitals and Training Load need Apple Watch. The page also lists an ECG app and sleep apnea notifications for Apple Watch. It does not mention a stress score.
[^a3]: Apple, Health and privacy: https://www.apple.com/legal/privacy/data/en/health-app/ . Data is encrypted on the device, iCloud sync is optional.
[^a4]: Apple, Health: https://www.apple.com/ios/health/ and the newsroom post above. Apple's page says the redesigned Health app is "coming in late 2026" (planned, not shipped). Readiness is described for Apple Watch Series 12 and Ultra 4, and the page gives it no separate date. Press said the redesigned Health app was pulled from the iOS 27.2 beta on 2026-10-13: https://www.channelnews.com.au/apple-pulls-redesigned-health-app-delays-major-upgrade/
[^a5]: Apple, Training Load on Apple Watch: https://support.apple.com/en-by/guide/watch/apd95450de2a/26/watchos/26
[^a6]: Apple newsroom post above (lab upload, Insights, Apple Intelligence: announced). Health Records import: https://support.apple.com/guide/iphone/download-health-records-iphc30019594/ios . Its scope was not readable on 2026-10-18, so it is described only as "some US providers".
[^a7]: Apple, Health: https://www.apple.com/ios/health/ . Mac and Vision Pro appear only for hearing, Sleep Focus and Mindfulness. No Health app for Mac was found, including in press coverage up to October 2026.
[^a8]: Apple, share your health data: https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios
[^a9]: Apple, Health and its privacy page: https://www.apple.com/ios/health/ and https://www.apple.com/legal/privacy/data/en/health-app/ . Neither links source code or a license. HealthKit is a closed Apple framework. The claim is that none is published, which no single page states.
[^a10]: Apple, Health: https://www.apple.com/ios/health/ and the Apple newsroom post in the first Apple note, which says only that a coming Longevity tab will draw on "third-party apps and devices". Apple's pages list no vendors.
[^o1]: Oura, Membership: https://support.ouraring.com/hc/en-us/articles/4409086524819-Oura-Membership (updated 2026-10-16) and https://ouraring.com/membership . Without membership only three daily scores are shown.
[^o2]: Oura, how it protects data: https://support.ouraring.com/hc/en-us/articles/360025586673-How-Oura-Protects-Your-Data
[^o3]: Oura privacy policy: https://ouraring.com/privacy-policy . Offline storage on the ring: https://ouraring.com/blog/airplane-mode/ . Whether the app shows cached scores with no connection is unconfirmed.
[^o4]: Oura, Membership page and https://ouraring.com/membership . No strain number and no energy score were found there.
[^o5]: Oura, Tags: https://ouraring.com/blog/tags/
[^o6]: Oura, Health Panels: https://ouraring.com/blog/health-panels/ . Panel $99, members with a Gen3 or Ring 4, most US states. The page says Lab Uploads was "rolling out June 30, 2026" and does not confirm it is live for everyone.
[^o7]: Oura, Advisor: https://ouraring.com/blog/oura-advisor
[^o8]: Oura, Partner Integrations: https://support.ouraring.com/hc/en-us/articles/43395088071443-Partner-Integrations
[^o9]: Oura on the App Store: https://apps.apple.com/us/app/oura/id1043837948 (iPhone, Apple Watch, Apple Vision). Android: https://ouraring.com/store/rings/oura-ring-4 . Web app existence is from Oura's own materials, and press says it may be discontinued, unconfirmed.
[^o10]: Oura, Membership: https://ouraring.com/membership ("export it as CSV without a membership"). The delivery window is from a support page summary and is not given here.
[^o11]: Oura public API (members only): https://cloud.ouraring.com/v2/docs , and the membership page https://ouraring.com/membership . They describe an API, not published app or firmware source. None found.
[^b1]: Bevel, pricing and what is free: https://help.bevel.health/en/articles/11583937 and the App Store listing https://apps.apple.com/us/app/bevel-all-in-one-health-app/id6456176249 . A 12 month commitment price of $10.99 per month exists outside the US and Singapore.
[^b2]: Bevel, connected sources: https://help.bevel.health/en/articles/10400449 . No Bevel page says what you get with an iPhone alone.
[^b3]: Bevel privacy policy (updated 2026-09-30): https://www.bevel.health/privacy-policy . It describes sign in, account deletion and a request by email for a copy of your data, in a format it does not state. Nothing outright says an account is required.
[^b4]: Bevel: https://www.bevel.health and the App Store listing above.
[^b5]: Bevel, Health Records: https://help.bevel.health/en/articles/11586369 and https://help.bevel.health/en/articles/11586753
[^b6]: Bevel Intelligence: https://help.bevel.health/en/articles/11586753 and https://help.bevel.health/en/articles/11583937
[^b7]: Bevel, connected sources: https://help.bevel.health/en/articles/10400449 . Whoop and Withings come from its feedback board: https://feedback.bevel.health/feature-requests/p/whoop-und-withings-integration
[^b8]: Bevel on the App Store (iPhone and Apple Watch) and its iPad request board: https://feedback.bevel.health/feature-requests/p/ipad-version . Android: Bevel staff said it will not come soon (reported by https://askvora.com/de/blog/bevel-for-android , a competitor's blog).
[^b9]: Bevel privacy policy https://www.bevel.health/privacy-policy , site https://www.bevel.health and App Store listing https://apps.apple.com/us/app/bevel-all-in-one-health-app/id6456176249 . None names a source repository or license. Press names the company as Finerpoint, Inc. in Whoop's complaint: https://the5krunner.com/2026/04/04/whoop-sues-bevel/
[^p1]: Prism code, see "How the Prism column was checked". Open-Meteo is a free weather service: https://open-meteo.com . The article and news feed need the Soma project key, which the public build does not ship today, so a build without the key reads only the bundled article library.
[^p2]: Prism code: `App/Prism/Core/Ask/AskClient.swift`, `supabase/functions/ask-soma/index.ts`, `App/Config/Cloud.xcconfig`.
[^p3]: Prism code: `HealthExportCore/Catalog/HealthMetricCatalog.swift` and `Core/Providers/DataProvider.swift`.
