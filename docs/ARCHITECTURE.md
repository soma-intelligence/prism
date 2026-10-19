# Architecture

Prism is one SwiftUI app target built for iPhone, iPad, Mac and Vision Pro, a widget extension, and two local Swift packages that hold most of the reusable code. A Supabase project in `supabase/` is the optional backend.

## Repository layout

| Path | What |
|---|---|
| `App/Prism.xcodeproj` | The Xcode project. Targets: `Prism`, `SomaWidgets`, `PrismTests`, `PrismUITests` |
| `App/Prism` | The app. A synchronized folder: any `.swift` file in it joins the target |
| `App/Prism/App` | Lifecycle, theme and Health injection |
| `App/Prism/Core` | Models, stores and engines, one folder per domain |
| `App/Prism/Features` | One folder per surface |
| `App/SomaWidgets` | The widget extension: scores, vitals, strain, fuel, log, and two Control Center buttons |
| `App/SomaWidgetKit` | Local package shared by the app and the widgets: the snapshot store and the widget views |
| `App/Config` | `Prism.xcconfig`, `Cloud.xcconfig`, `Signing.example.xcconfig` |
| `Packages/SomaUI` | The design system |
| `Packages/WellnessKit` | Apple Health reading, scoring, sync and cloud upload |
| `supabase` | Migrations, row level security, storage buckets, Edge Functions and their tests |
| `EXPORT.json` | The private commits this tree was exported from |

## The app

The shell is one `TabView` with four tabs. On a phone it's the system Liquid Glass tab bar, with Ask detached into its own disc. On iPad and Mac it becomes a sidebar.

| Tab | Parts | Code |
|---|---|---|
| Pulse | Today, Trends, Explore | `Features/Pulse` |
| Longevity | Body, Mind, Environment, with Labs under Body | `Features/Longevity` |
| Track | Journal, Rituals, Customize, with Tools from Rituals | `Features/Track`, `Features/Tools` |
| Ask | One conversation page and its history | `Features/Ask` |

Settings and the Vault open from the account button on every tab page.

Some `Core` folders worth knowing:

| Folder | Holds |
|---|---|
| `Core/Health` | `HealthDashboard`, the app's read of Apple Health, and `HealthAccess`, the single permission request |
| `Core/Scoring` | The app side of the scores: data gates and display |
| `Core/Lab` | Blood panel reading (`BloodReportReader`), the marker catalog, biological age (Levine's PhenoAge) and cardiometabolic risk (AHA PREVENT, CKD-EPI 2021) |
| `Core/Tools` | The engines behind the fifteen tools, plain functions over Health inputs |
| `Core/Journal`, `Core/Track`, `Core/Mind`, `Core/CheckIn` | The local stores behind Track and Mind |
| `Core/Articles` | The bundled article library and the optional online feed |
| `Core/Ask` | `AskClient`, `AskContextBuilder` and the history sync |
| `Core/Account`, `Core/Cloud` | Sign in with Apple, the Supabase settings, sync, export and delete |
| `Core/Providers` | Oura, Whoop and Withings sign in, switched off in this build |

Local data lives in SwiftData and in each store's files in the app container. Nothing in `Core` needs a network to compute a score.

## The packages

**SomaUI** has two products. `SomaUI` ships: tokens, `SomaTheme` and the components. `SomaUIPreviewSupport` holds preview fixtures and must never reach a shipping view. Components read `SomaTheme` from the environment and never take a colour, a size or copy as a parameter. Glass goes through `somaGlass(_:in:)`, which draws the system's Liquid Glass on iOS and macOS and the regular material on visionOS.

**WellnessKit** has six products:

| Product | Role |
|---|---|
| `HealthExportCore` | The metric catalog (192 entries), canonical units, permission scoping and the `HealthSampleSource` contract. No platform dependency |
| `HealthExportHealthKit` | `HealthKitSampleSource`, the HealthKit reader behind that contract |
| `HealthScoring` | `SomaScoringEngine`: sleep, recovery, strain, stress and energy from readings and personal baselines |
| `SyncCore` | One SQLite database per user, synced records with a transactional outbox, pull cursors, retries |
| `SyncSupabase` | The Supabase adapter over supabase-swift: Auth, the two sync RPC functions, Storage, Functions |
| `HealthCloud` | `HealthSampleUploader`: anchored Health reads uploaded to `health_samples`, plus daily rows |

## Data flow

1. Apple Health is asked once, for everything the app reads and writes. `HealthDashboard` reads through `HealthSampleSource`; in UI tests, `-health.empty YES` swaps in an empty source.
2. `HealthScoring` turns readings into the five daily scores on the device. The app's gates decide when there's enough data to show one; a missing value shows as a dash.
3. Track, Mind and Labs keep their own local stores.
4. With no backend configured, that's the whole loop, apart from location services. The Environment card asks Open-Meteo for weather at a location rounded to 0.1 degree (about 11 km), the only request to a service other than Apple's. Apple's MapKit names the place from a location rounded to 0.01 degree (about 1 km), names workout places on the Territory page from the middle of each group of routes rounded the same way (`Core/Location/CoarseCoordinate.swift`), searches cities on the Weather page, and draws the maps.
5. With a backend and a signed in person, `CloudSync` mirrors the stores into SyncCore's outbox, pushes and pulls through `sync_push` and `sync_pull`, uploads Health samples through `HealthCloud`, and keeps the profile and Ask history in step. [PRIVACY.md](../PRIVACY.md) lists exactly what goes.

## The backend

`supabase/` is a complete Supabase project:

- Migrations for the sync foundation, profiles and devices, Health samples, nine record tables, the article library, news, and Ask history with its hourly allowance. Every table has row level security, and a person reads and writes only their own rows.
- Two private storage buckets, `avatars` and `health-uploads`, one folder per person.
- Four Edge Functions: `ask-soma` (chat, streamed), `delete-account`, `news-ingest` and `articles-generate` (scheduled).
- SQL tests for the policies and Deno tests for the functions.

`supabase/README.md` documents every table and function. [SELF_HOSTING.md](SELF_HOSTING.md) shows how to run your own.

## Tests and guards

`App/PrismTests` holds the unit tests and three guards that walk the source: `StyleGuardTests` (the writing rules in `AGENTS.md`), `GlassGuardTests` (no direct glass calls) and `TypographyGuardTests` (fonts only through `.somaFont`). Each package has its own tests, run with `swift test`. The commands are in [CONTRIBUTING.md](../CONTRIBUTING.md).
