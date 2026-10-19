# Self hosting

Prism's backend is the Supabase project in `supabase/`: the database schema with row level security, two storage buckets, and four Edge Functions. You can run your own copy and point the app at it. Your users' accounts, synced records and Ask conversations then live in your project and nowhere else.

`supabase/README.md` is the full reference: every table, bucket and function, and the cost of running them. This page is the short path.

## What you need

- A Supabase project on supabase.com. The app only accepts an `https` address (`App/Prism/Core/Account/SupabaseSettings.swift`), so a local `supabase start` stack needs an HTTPS tunnel in front of it before the app will use it.
- The Supabase CLI, signed in (`supabase login`).
- An Apple developer team, for Sign in with Apple. It's the only sign in the app offers. Onboarding shows Sign in with Apple and "Not now", with no email or password entry: the email screen is written but hidden behind `OnboardingSignInOptions.offersEmail` (`App/Prism/Features/Onboarding/OnboardingSignIn.swift`), because no account service behind it can sign anyone in yet. Email sign in is planned (see `ROADMAP.md`). There's no Google sign in either.
- For Ask, news summaries and generated articles: a chat model deployment on Azure that speaks the OpenAI v1 chat completions API. Without one, accounts, sync, export and delete still work; Ask's model answers and the news and article jobs don't.

## 1. Name your project

Set `project_id` in `supabase/config.toml` to a name of your own. It only labels the local stack, but it still carries the name of the project this folder came from.

The two cron migrations, `20261003120600_news_items.sql` and `20261003120700_article_generation.sql`, need no editing. They hold no project address: each cron job reads it from a Vault secret named `project_url`, next to the `service_role_key` secret that holds the key it sends. You store both in step 5. Until `project_url` exists, the jobs log a warning and do nothing, so your key can't go to a project you didn't name.

## 2. Database and storage

```bash
supabase link --project-ref <your project ref>
supabase db push
```

`db push` applies `supabase/migrations` in order, buckets included. Then, in the dashboard:

- Storage, Settings: raise the global upload limit to at least 200 MB, the `health-uploads` bucket's own limit, or the largest exports fail.
- Database, Extensions: check that `pg_cron` and `pg_net` are on.

## 3. Sign in with Apple

1. In your Apple developer account, turn on Sign in with Apple for your app's identifier (the bundle id you set in `App/Config/Signing.xcconfig`).
2. In Xcode, add the Sign in with Apple capability to the Prism target. Neither `App/Prism.entitlements` nor `App/Prism-macOS.entitlements` carries `com.apple.developer.applesignin`, so that a build without your identifier still works. Until you add it under your own team, the Apple button fails at the system's sign in sheet and no account can be made.
3. In the Supabase dashboard, Authentication, Providers, Apple: enable it and add your bundle id to Client IDs. The app's native flow needs no secret.

For a local stack, the same values go in `SUPABASE_AUTH_EXTERNAL_APPLE_CLIENT_ID` and `SUPABASE_AUTH_EXTERNAL_APPLE_SECRET`, which `config.toml` reads.

## 4. The app's address and key

In the dashboard, Project Settings, API, copy the project URL and the publishable key (`sb_publishable_...`, or the legacy anon key). Put them in `App/Config/Cloud.xcconfig`, or in a new `App/Config/Supabase.xcconfig`, which is git ignored and read after `Cloud.xcconfig`:

```
SOMA_SUPABASE_URL = https:/$()/<your project ref>.supabase.co
SOMA_SUPABASE_PUBLISHABLE_KEY = sb_publishable_...
```

An xcconfig reads `//` as the start of a comment, so the address is written with an empty `$()` between the slashes and Xcode joins it back.

Only the publishable key goes in the app. The secret and service role keys stay on the server: Supabase hands them to the functions itself.

## 5. Functions

Set the secrets your functions read:

```bash
supabase secrets set --project-ref <your project ref> \
  AZURE_OPENAI_ENDPOINT=https://<your resource>.openai.azure.com \
  AZURE_OPENAI_API_KEY=<resource key> \
  AZURE_OPENAI_DEPLOYMENT=<deployment name for Ask> \
  FOUNDRY_ENDPOINT=https://<your resource>.services.ai.azure.com \
  FOUNDRY_API_KEY=<resource key> \
  FOUNDRY_MODEL=<deployment name for news summaries> \
  FOUNDRY_ARTICLE_MODEL=<deployment name for articles>
```

Optional: `ASK_PER_HOUR` (messages per person per hour, default 60), `ARTICLES_AUTO_PUBLISH` (default off, so drafts wait for you), `ARTICLES_WINDOW_DAYS`, `ARTICLES_MIN_ITEMS`, `ARTICLES_MAX_PER_RUN`, `NEWS_MAX_NEW`, `NEWS_MAX_AGE_DAYS`.

Then deploy:

```bash
supabase functions deploy ask-soma delete-account news-ingest articles-generate --project-ref <your project ref>
```

`ask-soma` and `delete-account` only accept a signed in person. `news-ingest` and `articles-generate` run on a schedule and check the service role bearer themselves.

The news and article schedules read two secrets from Vault. In the SQL editor:

```sql
select vault.create_secret('<service_role JWT>', 'service_role_key', 'Bearer for the news and article functions');
select vault.create_secret('https://<your-ref>.supabase.co', 'project_url', 'Base address of this project');
```

`service_role_key` is the legacy `service_role` JWT from Project Settings, API Keys, Legacy API keys. `project_url` is your project's address with no path. `supabase/README.md`, section 5, has the details and the first dry runs.

To use a model that isn't on Azure, change the request the functions build: `supabase/functions/ask-soma` for Ask, `supabase/functions/_shared/foundry.ts` for news and articles.

## 6. Build and check

Build the app with your address and key, sign in with Apple, and check that a journal entry appears in `journal_days` for your user. Settings, Data, Export my data and Delete my data exercise the storage bucket and the `delete-account` function.

The backend has its own tests:

```bash
supabase/scripts/local-test/run.sh     # the SQL checks, on a scratch Postgres 17 from Homebrew, no Docker
supabase/scripts/test-functions.sh     # every function's tests, with Deno (or Bun)
```

With Docker and the CLI, `supabase start && supabase db reset && supabase db test` runs the same SQL files with pgTAP.
