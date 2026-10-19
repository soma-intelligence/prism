# WellnessKit

The Soma engines for health data export, food and exercise, as one Swift package.

This first version holds the foundation every kit builds on. The kits themselves
(health export, wearable links, food, exercise) come next, each with its own
specification and plan in `docs/`.

| Module | Status | Role |
|---|---|---|
| `SyncCore` | done | One SQLite database per user, synced records with a transactional outbox, pull cursors, a one-way upload journal, typed remote errors, retry and authentication, session composition |
| `SyncSupabase` | done | The Supabase adapter: two Postgres RPC functions for records, Storage for objects, and `SupabaseServices` / `SupabaseAccountAuth` over supabase-swift |
| `HealthCloud` | done | `HealthSampleUploader`: anchored Health reads to `health_samples`, daily rows, persisted anchors and backoff |
| `HealthExportCore` | read layer done | The metric catalog (192 entries: every quantity, category, correlation, the workout type and the characteristics), canonical units, permission scoping, and the `HealthSampleSource` contract. No platform dependency, so it compiles and tests anywhere |
| `HealthExportHealthKit` | read layer done | `HealthKitSampleSource`: runtime type resolution from the catalog's identifiers, cancellable async queries, statistics and durations. Reduces to an unavailable stub where there is no Health store |
| `HealthScoring` | done | `SomaScoringEngine`: sleep, recovery, strain, stress and energy from health readings and personal baselines. Missing inputs stay optional |
| Export pipeline, `WearableLinkCore` | next | The planner, NDJSON and gzip, deterministic keys, background delivery, and the wearable links |
| `FoodCore`, `FoodVision`, `FoodCapture`, `FoodHealthKit`, `FoodAdmin` | planned | Food sub-project |
| `ExerciseCore` | planned | Exercise sub-project |

Design: `docs/specs/2026-09-16-wellnesskit-foundation-design.md`.
Implementation plan: `docs/plans/2026-09-16-foundation-plan.md`.

## Requirements

iOS 26, visionOS 26, macOS 26. Swift 6 language mode. One third-party dependency: the official Supabase client (supabase-swift, from 2.55.3), used by `SyncSupabase` for Auth, PostgREST, Storage and Functions.

## Using the foundation

```swift
import SyncCore
import SyncSupabase

let supabase = SupabaseConfiguration(projectURL: url, publishableKey: key, storageBucket: "health-raw")
let session = try await WellnessSession.open(
    WellnessEnvironment(
        userID: UserID(user.id),
        tokens: authBridge,                       // your AccessTokenProvider
        records: SupabaseRecordStore(configuration: supabase),
        objects: SupabaseObjectStore(configuration: supabase),
        logSubsystem: "app.soma"
    ),
    modules: [notesModule]                        // each kit's SchemaModule
)

let notes = session.repository(for: Note.self)    // Note: SyncRecord
try await notes.save(Note(id: session.ids.next(), body: "hello"))
for await batch in session.changes { /* update the UI */ }

await session.close()                             // on sign-out
```

A record type is a `Codable` value with an `id` and a `recordType`. Its table is
created by `SyncTable.createStatement(for:)` in the kit's migration, and on the
server by `select public.sync_create_record_table('<record_type>', 'soma_<plural>')`.

## Reading Apple Health

```swift
import HealthExportCore
import HealthExportHealthKit

let source = HealthKitSampleSource()
try await source.requestAuthorization(for: HealthMetricCatalog.launchRequest)

let steps = HealthMetricCatalog.metric(for: "HKQuantityTypeIdentifierStepCount")!
let today = try await source.summary(steps, from: startOfDay, to: .now)   // sums, because steps are cumulative
let asleep = try await source.totalDuration(sleep, from: lastEvening, to: .now,
                                            codes: HealthCategoryValue.asleep)
```

The catalog names types by their HealthKit identifier **string**, not by an SDK
symbol. A catalog built from symbols stops compiling the moment it names a type
the current SDK lacks; this one names them all and lets the platform resolve what
it knows, so a new metric costs one line and an older OS simply skips it.

`HealthMetricCatalog.launchRequest` excludes every sensitive metric by
construction. Cycle tracking and basal body temperature are in `onDemand`
instead, so the first permission sheet cannot sweep in reproductive health
nobody asked to share; the surface that needs it requests it when it opens.

## Guarantees, each enforced by a test

- A write and its outbox entry commit together (a crash test that this tree does not ship).
- An edit made while its row is being pushed is pushed again (`SyncAgentPushTests`).
- The pull cursor never passes a page that was not applied (a crash test that this tree does not ship).
- Two users never share rows, outbox or cursors: one directory and one lock per user (`WellnessSessionTests`).
- A row that cannot be decoded is quarantined; the others stay readable (`RecordRepositoryTests`).
- A failed migration leaves the store failed; there is no in-memory fallback (`LocalStoreTests`).
- Conflicts: the server wins by default and the discarded value is published (`SyncAgentPushTests`).
- An upload position moves only when every object is confirmed; a crash neither loses nor duplicates (`UploadJournalTests`, and a crash test that this tree does not ship).
- Backoff and `Retry-After` persist across relaunches; offline consumes no attempt; a circuit breaker stops hammering (`SyncAgentPushTests`).
- One token refresh and one retry on 401; offline refresh never signs the user out (`TokenGateTests`).
- Devices converge under random edits, faults and crashes (`ModelBasedSyncTests`).

## Verifying

```bash
swift test
WELLNESSKIT_MODEL_SEQUENCES=10000 swift test --filter ModelBasedSyncTests
./verify-ios.sh
```

If `swift` or `git` fail with a missing developer directory, export
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` first.

Server side, with Docker running and the Supabase CLI installed:

```bash
supabase init        # once, creates supabase/config.toml
supabase start
supabase db reset    # applies supabase/migrations
supabase db test     # runs supabase/tests with pgTAP
```

## Repository rules

`RepositoryGuardTests` fail the build when a file contains a legacy brand name,
an em-dash, or a `try?` in `Sources/` that is not listed with a justification in
`Tests/Allowlists/try-optional.txt`.
