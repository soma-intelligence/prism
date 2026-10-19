# Prism's Supabase project

Everything the app keeps online lives in one Supabase project: the database with
row level security, two private storage buckets and four Edge Functions. This
folder is that project. You can run your own copy and point the app at it; the
short path is [docs/SELF_HOSTING.md](../docs/SELF_HOSTING.md) at the root of the
repository, and this page is the reference behind it.

Nothing here is applied for you. The steps below are for whoever runs the
project, once the Supabase CLI is signed in. Run every command from the root of
the repository.

## What is here

| Path | What |
| --- | --- |
| `config.toml` | CLI configuration: project id, Auth (Sign in with Apple), Storage limit, the four functions |
| `migrations/20261003115900_extensions.sql` | pg_cron, pg_net |
| `migrations/20261003120000_sync_foundation.sql` | The record sync contract of WellnessKit's SyncCore: `sync_push`, `sync_pull`, tombstones |
| `migrations/20261003120100_profiles_devices.sql` | `profiles` (made by a trigger on sign up), `devices`, `delete_my_account()` |
| `migrations/20261003120200_health.sql` | `health_samples`, `health_daily`, `health_sync_state` |
| `migrations/20261003120300_app_records.sql` | The nine synced record tables with typed columns |
| `migrations/20261003120400_storage.sql` | Buckets `avatars` and `health-uploads`, folder policies |
| `migrations/20261003120500_app_articles.sql` | Explore's article library |
| `migrations/20261003120600_news_items.sql` | Explore's news, its six-hourly tick and retention |
| `migrations/20261003120700_article_generation.sql` | Generated article columns, the daily tick |
| `migrations/20261003120800_ask.sql` | Ask history and hourly allowance |
| `migrations/20261003120900_ask_conversations.sql` | `ask_conversations`, messages linked to it, idempotent client ids |
| `functions/news-ingest` | Feeds to `news_items`, summaries by a chat model (its own README) |
| `functions/articles-generate` | One article per topic from the week's news, by a chat model, as drafts |
| `functions/ask-soma` | The Ask chat, on a chat model deployment of yours, streamed |
| `functions/delete-account` | Deletes the caller's files and account |
| `functions/_shared` | HTTP retries, the chat model call, JSON answers |
| `tests/*.sql` | Row level security, schema and cron tick checks (pgTAP style) |
| `scripts/local-test/` | `run.sh` runs the SQL tests on a scratch Postgres 17 with no Docker; `shims.sql` and `pgtap-lite.sql` stand in for what a hosted project provides |
| `scripts/test-functions.sh` | Runs every function's tests (Deno, or Bun when Deno is missing) |

## Data model

Every table has row level security: a signed in person reads and writes only
their own rows (`user_id = auth.uid()`, or `id` for `profiles`), `anon` gets
nothing, and the service role has every privilege. Content tables are the
exception: `app_articles` and `news_items` are readable by anyone, writable by
the service role only.

| Table | One row per | Written by | Key columns |
| --- | --- | --- | --- |
| `profiles` | account | trigger on `auth.users`, then the app | first name, birth date, sex, height, units, focus, chronotype, `avatar_path` |
| `devices` | installation | the app at each sync | installation id, platform, model, versions, push token (later) |
| `health_samples` | Health sample | Health upload | `(user_id, hk_uuid)` unique, metric, value, unit, start, end, source, bundle, device, model, typed in |
| `health_daily` | metric and local day | Health upload | sum (deduplicated by Health), avg, min, max, count |
| `health_sync_state` | installation and metric | Health upload | anchor (base64), last synced, samples so far |
| `journal_days` | day | outbox | day, `tags_yes`, `tags_no`, feeling 0 to 6 |
| `check_in_answers` | day and question | outbox | answer kind and value, skipped |
| `mood_logs` | mood | outbox | time, kind, valence -1 to 1, labels, associations, origin |
| `mind_check_ins` | check-in | outbox | energy, mood, focus 0 to 4, question, answer |
| `track_logs` | logged item | outbox | kind (drink, meal, dose, supplement, practice, fast, measure, wake_rating), time, value, unit, detail |
| `lab_results` | blood panel | outbox | collected on, markers |
| `scores_daily` | day | outbox | sleep, recovery, strain, stress, energy |
| `notification_inbox` | delivered notification | outbox | time, kind, title, read |
| `provider_connections` | linked service | outbox | provider, status, account label, last sync; a payload naming a token is refused |
| `ask_conversations` | chat | the app, ask-soma | kind (`ask`), title, created, updated, archived, last message preview, model |
| `ask_messages` | chat message | ask-soma, the app | conversation, `client_id` (`<turn>:user` or `<turn>:assistant`, unique per person), role, content, model, tokens, error flag, `meta` (sources, move) |
| `ask_usage` | person and hour | `ask_take_quota()` | messages |
| `app_articles` | article | the project admin, articles-generate | slug, topic, body, sources, `published`, `generated_by`, `model` |
| `news_items` | news item | news-ingest | source, link, our summary, topics |

The outbox tables share the sync foundation's layout (`id`, `user_id`,
`revision`, `deleted`, `payload`, `updated_at`); a trigger copies the payload
into the typed columns on every write and never fails a push over an odd value.

Buckets, both private, one folder per person (`<user id>/...`):

| Bucket | Holds | Limit | Types |
| --- | --- | --- | --- |
| `avatars` | `<uid>/avatar.jpg` | 5 MB | JPEG, PNG, HEIC |
| `health-uploads` | `<uid>/exports/<date>.zip` and data files | 200 MB | JSON, CSV, ZIP, NDJSON, gzip |

## How the app uses it

- **Sign in with Apple.** `SignInWithAppleButton` puts the SHA-256 of a fresh
  nonce on the Apple request; `AccountSession` sends Apple's identity token and
  the raw nonce to Supabase Auth (`signInWithIdToken`, provider apple) through
  the official client, supabase-swift, which keeps the session in the Keychain
  and refreshes it. Sign out is on the account page.
- **Records.** Each local store stays as it is. `CloudMirror` compares what a
  store holds with what was last pushed and saves the difference into
  SyncCore's outbox, which pushes through `sync_push` with retries and backoff,
  and pulls the person's records back on a new phone. Ids of day based records
  are derived from the person and the day, so two phones write one row.
- **Health.** `HealthSampleUploader` (WellnessKit, HealthCloud) reads each
  metric with HealthKit anchored queries, upserts pages of 500 on
  `(user_id, hk_uuid)`, deletes what Health deleted, stores the anchor only
  after the server confirmed, then writes the touched days to `health_daily`
  from Health's own statistics. It runs only after the one Health sheet was
  answered, when the app comes forward and in a background processing task.
  Sensitive metrics (cycle tracking and the like) stay on the phone.
- **Profile and photo.** Pushed when they change; a new phone fills what it
  lacks from the server, the photo included.
- **Export my data.** `DataExport.run(upload:)` writes a ZIP (profile, photo,
  one JSON per table, Health samples as NDJSON) and can upload it to
  `health-uploads/<uid>/exports/<date>.zip`.
- **Delete my data.** `AccountDeletion.run()` calls `delete-account`.
- **Ask.** `AskClient.stream(messages:context:conversationID:turnID:)` posts
  to `ask-soma` with the session's token and yields the answer as it streams.
  The function opens the conversation (titled from the first question, then
  renamed by the model in a few words) and stores both messages under the
  page's turn id. `AskHistorySync` mirrors the drawer both ways on every
  pass, on launch and on the drawer's pull to refresh: every kept turn goes
  up once (answers given offline and turns from before sign in included,
  `on_conflict=user_id,client_id` with duplicates ignored), conversations
  from other phones come down and merge by turn id, and a delete in the
  drawer deletes the conversation and its messages.

## Applying it

### 1. Link and push the database

```bash
supabase login
supabase link --project-ref <your project ref>
supabase db push            # applies supabase/migrations in order, buckets included
```

`supabase/config.toml` carries the `project_id` of the project this folder came
from. It only names the local stack's containers, so it does not decide where
`db push` goes, but set it to a name of your own so two stacks on one machine do
not mix.

Then, in the dashboard:

- Storage, Settings: raise the global upload size limit to at least 200 MB
  (the `health-uploads` bucket's own limit), or the largest exports fail.
- Database, Extensions: check that `pg_cron` and `pg_net` are on (the first
  migration enables them).

### 2. Sign in with Apple

Apple Developer (your team):

1. Identifiers, your app's App ID: tick **Sign in with Apple**, save. The
   provisioning profiles regenerate.
2. In Xcode, add the capability to the Prism target (Signing & Capabilities,
   + Capability, Sign in with Apple). It writes this into `App/Prism.entitlements`:
   ```xml
   <key>com.apple.developer.applesignin</key>
   <array><string>Default</string></array>
   ```
   It is not in the file on purpose: added before step 1, every macOS and
   visionOS build fails on a profile without the capability.
3. Only for a web sign in later: a Services ID with the return URL
   `https://<your project ref>.supabase.co/auth/v1/callback`, and a Sign in
   with Apple key (Keys, +, Sign in with Apple). Its secret is a JWT made from
   the key, the key id and the team id, valid six months (a short script that
   signs one with the key is enough).

Supabase dashboard, Authentication, Sign In / Providers, Apple:

- Enable it.
- Client IDs: your app's bundle id (and the Services ID if there is one). The
  native flow checks the identity token's audience against this list; no secret
  is needed for it.
- Secret key: only with a Services ID, the JWT from step 3.

For the local stack, the same values go in `SUPABASE_AUTH_EXTERNAL_APPLE_CLIENT_ID`
and `SUPABASE_AUTH_EXTERNAL_APPLE_SECRET` (read by `config.toml`).

### 3. The app's address and key

Dashboard, Project Settings, API: copy the project URL and the publishable key
(`sb_publishable_...`, or the legacy anon key). Put them in `App/Config/Cloud.xcconfig`,
or in `App/Config/Supabase.xcconfig`, which is git ignored and read after it:

```
SOMA_SUPABASE_URL = https:/$()/<your project ref>.supabase.co
SOMA_SUPABASE_PUBLISHABLE_KEY = sb_publishable_...
```

An xcconfig reads `//` as a comment, hence `https:/$()/`. The `Prism-Info.plist`
keys `SomaSupabaseURL` and `SomaSupabasePublishableKey` take the values at build
time; Explore's article reader uses the same pair. Never put the service role
key in the app. With an empty key the app builds and runs with no account,
everything on the phone.

### 4. Functions

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are set by
Supabase. The others are yours:

| Variable | Used by | Meaning |
| --- | --- | --- |
| `FOUNDRY_ENDPOINT`, `FOUNDRY_API_KEY` | news-ingest, articles-generate | Address and key of an Azure AI Foundry resource |
| `FOUNDRY_MODEL` | news-ingest | Deployment name for news summaries |
| `FOUNDRY_ARTICLE_MODEL` | articles-generate | Deployment name for articles |
| `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_API_KEY` | ask-soma | Address and key of an Azure OpenAI resource |
| `AZURE_OPENAI_DEPLOYMENT` | ask-soma | Deployment name for Ask |
| `ASK_PER_HOUR` | ask-soma | Messages per person per hour, default 60 |
| `ARTICLES_AUTO_PUBLISH` | articles-generate | `true` publishes at once; default off, drafts wait for you |
| `ARTICLES_WINDOW_DAYS`, `ARTICLES_MIN_ITEMS`, `ARTICLES_MAX_PER_RUN` | articles-generate | How much news a run reads and how many articles it writes |
| `NEWS_MAX_NEW`, `NEWS_MAX_AGE_DAYS` | news-ingest | How many new items a run keeps and how old they may be |

```bash
supabase secrets set --project-ref <your project ref> \
  FOUNDRY_ENDPOINT=https://<your resource>.services.ai.azure.com \
  FOUNDRY_API_KEY=<resource key> \
  FOUNDRY_MODEL=<deployment name for news summaries> \
  FOUNDRY_ARTICLE_MODEL=<deployment name for articles> \
  AZURE_OPENAI_ENDPOINT=https://<your resource>.openai.azure.com \
  AZURE_OPENAI_API_KEY=<resource key> \
  AZURE_OPENAI_DEPLOYMENT=<deployment name for Ask>
```

A model is addressed by the deployment name you gave it on your resource, never
by the catalog name. Each function falls back to a default deployment name
defined in its own `index.ts` when its variable is unset. A smaller, cheaper
deployment suits news summaries, a larger one suits articles and chat; they can
be the same. To use a model that is not on Azure, change the request the
functions build: `functions/ask-soma` for Ask, `functions/_shared/foundry.ts`
for news and articles.

Deploy:

```bash
supabase functions deploy news-ingest articles-generate ask-soma delete-account --project-ref <your project ref>
```

`config.toml` sets `verify_jwt`: on for `ask-soma` and `delete-account` (a
signed in person only), off for the two cron functions, which check the
service role bearer themselves.

### 5. News and generated articles

The two cron ticks (`news_ingest_tick` every six hours, `articles_generate_tick`
daily) read two secrets from Vault, in the SQL editor:

```sql
select vault.create_secret('<service_role JWT>', 'service_role_key', 'Bearer for the news and article functions');
select vault.create_secret('https://<your project ref>.supabase.co', 'project_url', 'Base address of this project');
```

`service_role_key` is the legacy `service_role` JWT (Project Settings, API Keys,
Legacy API keys), the value the functions see as `SUPABASE_SERVICE_ROLE_KEY`. If
legacy keys are turned off, keep the Vault value equal to what the functions
see. `project_url` is where the ticks send that key: the migrations carry no
address of their own, so the key goes only to the project you name. A tick
that finds either secret missing logs a warning and does nothing, so the
migrations are safe to apply before the secrets exist.

Check a deployment before relying on it:

```bash
curl -s "$FOUNDRY_ENDPOINT/openai/v1/chat/completions" \
  -H "Content-Type: application/json" -H "api-key: $FOUNDRY_API_KEY" \
  -d "{\"model\":\"$FOUNDRY_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Say ok.\"}]}"
```

First runs, dry first (nothing stored, the drafts come back in the answer):

```bash
curl -s -X POST https://<your project ref>.supabase.co/functions/v1/news-ingest \
  -H "Authorization: Bearer $SERVICE_ROLE_JWT" -H "Content-Type: application/json" \
  -d '{"dryRun": true, "wait": true, "maxNew": 3}'
curl -s -X POST https://<your project ref>.supabase.co/functions/v1/articles-generate \
  -H "Authorization: Bearer $SERVICE_ROLE_JWT" -H "Content-Type: application/json" \
  -d '{"dryRun": true, "wait": true, "maxArticles": 1}'
```

Generated articles land with `published = false`. Read them in the Table
Editor (`app_articles` where `generated_by = 'articles-generate'`) and set
`published` to true to release one; its date fills itself. Each carries its
model, its news items (`source_news_ids`) and its sources, and the app says it
was written automatically.

```sql
select source_name, title, summary, topics from public.news_items order by created_at desc limit 10;
select slug, title, published, model from public.app_articles where generated_by is not null order by created_at desc;
select * from cron.job_run_details order by start_time desc limit 10;
```

To stop either: `select cron.unschedule('news-ingest');`,
`select cron.unschedule('articles-generate');`.

### 6. Ask

The Azure OpenAI v1 API: `POST <endpoint>/openai/v1/chat/completions`, header
`api-key`, body `{"model": "<deployment name>", "messages": [...], "stream": true}`,
no `api-version`
([Microsoft Learn, v1 API](https://learn.microsoft.com/azure/ai-foundry/openai/api-version-lifecycle)).
Check the deployment answers:

```bash
curl -s "$AZURE_OPENAI_ENDPOINT/openai/v1/chat/completions" \
  -H "Content-Type: application/json" -H "api-key: $AZURE_OPENAI_API_KEY" \
  -d "{\"model\":\"$AZURE_OPENAI_DEPLOYMENT\",\"messages\":[{\"role\":\"user\",\"content\":\"Say ok.\"}]}"
```

## Testing

```bash
supabase/scripts/local-test/run.sh     # SQL: 95 checks on a scratch Postgres 17 (Homebrew), no Docker
supabase/scripts/test-functions.sh     # functions: 45 tests (Deno, or Bun with stand-ins)
```

`run.sh` needs Homebrew's `postgresql@17`. It applies the migrations in order
to a throwaway cluster, with `shims.sql` standing in for the roles, `auth`,
`storage`, Vault, pg_cron and pg_net of a hosted project, and runs each file of
`tests/`. Pass a file name to run one: `run.sh cron_ticks_test.sql`.

With Docker and the CLI, `supabase start && supabase db reset && supabase db test`
runs the same SQL files with pgTAP.

## Cost

- Health and records: database and storage only. A heavy Health history is a
  few million rows; the Pro plan's included 8 GB holds years for a small
  number of people.
- News summaries: under 1 USD a month (the news-ingest README has the sums).
- Generated articles: at most 3 a day, each about 1,500 input and 1,000 output
  tokens, twice when a draft is refused. Multiply by your deployment's price
  per million tokens (see its pricing page); at typical prices for a mid-size
  chat model that is a few cents a day.
- Ask: one call per message, about 1,500 input tokens (prompt, context,
  history) and 200 output. The hourly allowance (60) caps one person's spend.

## Not done yet

- Restoring a new phone's local stores (Journal, Track, Mind) from the pulled
  records: the records come down into the sync database, the stores do not read
  them yet.
- Push notifications (the `devices.push_token` column waits for APNs).
