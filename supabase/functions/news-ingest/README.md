# News pipeline: health and wellness news for Explore

The pipeline belongs to the app's own Supabase project (`qnysyehawitnlcnccyop`), not the
website's. Nothing is applied or deployed. The migration is `supabase/migrations/20261003120600_news_items.sql`; the go-live steps are in
`supabase/README.md` ("News and generated articles").

## What it does

Every six hours pg_cron calls `public.news_ingest_tick()`, which has pg_net post to the Edge
Function `news-ingest` with the service role key kept in Vault. The function:

1. Reads the enabled feeds in `functions/news-ingest/feeds.ts` (4 at a time, 15 s timeout, one
   retry).
2. Keeps items from the last 14 days whose link is not in `public.news_items`, at most 4 per
   feed, taken round-robin across feeds so one busy feed can't fill a run.
3. For each, reads the article's `<head>` only (300 KB cap) for its canonical URL, its share
   image and its meta description. The CDC's feed links through a redirect, so the stored
   `source_url` is the page it lands on.
4. Sends the headline, the publisher, the feed categories and the feed's own excerpt (never the
   article) to a chat deployment on Azure AI Foundry, which answers
   `{"summary": "...", "topics": [...]}`. The answer is checked in code: 2 or 3 sentences, 40
   to 700 characters, 1 to 3 topics from `sleep, heart, recovery, movement, nutrition, mind,
   longevity, research`, no hype words, no "you", no "cure", no exclamation mark. Dashes become
   commas. A refused answer gets one second try with the reason; then the item is skipped (and
   tried again next run while it stays within 14 days).
5. Inserts title, link, summary, topics, image URL (only for sources whose terms allow it),
   source name, publication date and the deployment name. `on_conflict=source_url` with
   `ignore-duplicates`, so two overlapping runs can't store an item twice.

Limits: 20 new items per run (`NEWS_MAX_NEW`, at most 50), one model call every 1.5 s, 30 s per
model call with 3 attempts (backoff, honours `Retry-After`), and no new item is started after
120 s. The function answers 202 at once and works in the background
(`EdgeRuntime.waitUntil`). Each step writes one JSON log line (`feed_read`, `feed_failed`,
`candidates`, `item_stored`, `summary_refused`, `item_failed`, `run_finished` with counts and
token usage).

The app reads `news_items` with the publishable key: RLS shows rows published in the last 60
days to `anon` and `authenticated`; only `service_role` writes. A daily job deletes rows older
than 180 days.

## Files

| File | What |
| --- | --- |
| `../../migrations/20261003120600_news_items.sql` | Table, indexes, RLS, grants, `news_ingest_tick()`, the two cron jobs |
| `index.ts` | Handler and the run |
| `feeds.ts` | The curated feed list and each feed's rules |
| `parse.ts` | RSS and Atom parsing, page meta, candidate picking |
| `prompt.ts` | The prompt and the check of the model's answer |
| `../_shared/foundry.ts` | Foundry chat completions call |
| `db.ts` | PostgREST reads and inserts |
| `../_shared/http.ts` | Timeouts, retries, size caps, logs |
| `*_test.ts`, `fixtures/` | Deno tests on synthetic fixtures |

No third-party dependency: plain `fetch` for the feeds, Foundry and PostgREST. The tests import
`jsr:@std/assert@1`.

## Model and cost

Model: the deployment named by `FOUNDRY_MODEL`. A small, non-reasoning chat model is
enough: a three sentence summary of a short excerpt needs no reasoning model, and a model
that is generally available (not preview) will not change under the function.

Price: whatever your deployment's price per million input and output tokens is. The
estimate below assumes 0.20 USD per million input tokens and 0.50 USD per million output
tokens, a typical price for a small model; confirm the real figures on the Foundry pricing
page before relying on them.

Estimate at about 80 summaries a day (2,400 a month), with about 600 input and 120 output
tokens per call and 10 % second tries:

| | Tokens a month | Cost a month |
| --- | --- | --- |
| Input | about 1.6 M | about 0.32 USD |
| Output | about 0.32 M | about 0.16 USD |
| **Total** | | **under 1 USD** |

The real volume is lower: on 2026-10-03 the enabled feeds held 62 items from the last 14 days,
about 5 a day. Supabase side: about 120 function invocations a month, inside any plan.

## Feeds

Checked on 2026-10-03 with a plain HTTP client.

Kept (enabled):

| Feed | URL | Images |
| --- | --- | --- |
| ScienceDaily, Health and Medicine | `https://www.sciencedaily.com/rss/health_medicine.xml` | no |
| ScienceDaily, Sleep Disorders | `https://www.sciencedaily.com/rss/mind_brain/sleep_disorders.xml` | no |
| ScienceDaily, Fitness | `https://www.sciencedaily.com/rss/health_medicine/fitness.xml` | no |
| ScienceDaily, Nutrition | `https://www.sciencedaily.com/rss/health_medicine/nutrition.xml` | no |
| ScienceDaily, Heart Disease | `https://www.sciencedaily.com/rss/health_medicine/heart_disease.xml` | no |
| ScienceDaily, Healthy Aging | `https://www.sciencedaily.com/rss/health_medicine/healthy_aging.xml` | no |
| ScienceDaily, Mental Health | `https://www.sciencedaily.com/rss/mind_brain/mental_health.xml` | no |
| CDC Online Newsroom | `https://tools.cdc.gov/api/v2/resources/media/132608.rss` | yes, logos dropped |
| American College of Sports Medicine | `https://www.acsm.org/rss` | no; "Member Exclusive" items skipped |

Kept in the list but disabled: WHO news (`https://www.who.int/rss-feeds/news-english.xml`,
valid but its newest item is from 2026-02-25) and Nature Medicine
(`https://www.nature.com/nm.rss`, current but clinical trials rather than wellness reading).

Dropped, did not answer with a feed: NIH News in Health (`newsinhealth.nih.gov/rss`, 403), NIH
news releases (`nih.gov/news-events/news-releases/feed.xml`, 403), Harvard Health Blog (no
site-wide feed; `/blog/feed` is 404 and the per-author feeds are empty), Stanford Medicine news
(404 and an empty `news.xml`), Mayo Clinic News Network (`newsnetwork.mayoclinic.org/feed/`,
403), AHA newsroom (403 or HTML), Johns Hopkins (403), NIA, NHLBI, NCCIH and MedlinePlus news
(404). The 403s are bot walls; they may answer another client, but the function would meet the
same wall.

### Adding or removing a feed

Edit `FEEDS` in `feeds.ts` and redeploy the function. Before adding one:

1. `curl -sL -A "SomaNewsBot/1.0 (+https://www.somalabs.me)" <url> | head -c 600` shows `<rss`
   or `<feed`, and recent `<pubDate>` or `<updated>` dates.
2. Read the source's terms: may a headline and link be shown, and may its images be hotlinked?
   Set `images` accordingly (false when unsure). `linkMustInclude` and `skipCategories` narrow
   what is taken.
3. Add a test with a fixture if the feed's shape is new (another namespace for images, an
   unusual date format).

To pause a feed without losing its vetting, set `enabled: false`. Rows already stored stay
until retention removes them; delete them by `source_name` if a source must go at once.

## Licensing notes

What is stored and shown is a headline, a link to the source, our own summary written from the
feed's excerpt, the source's name and, for some sources, a hotlinked image URL. No article text
is copied or stored. The app should show the source name with each item and open the
`source_url` itself (no framing, no intermediate page).

- **ScienceDaily** ([terms](https://www.sciencedaily.com/terms.htm)): headlines and summaries of
  `/releases/` stories may be reproduced with a working link to the full story and credit to
  ScienceDaily; only `/releases/` links are taken. Their images are for personal use only, so
  `images: false`. Their terms also object to storing their content in a database: we store
  their headline and our own summary, not their summary. Treat that as a point to confirm with
  ScienceDaily or counsel before launch.
- **CDC** ([content reuse](https://www.cdc.gov/other/agencymaterials.html)): mostly public
  domain. Credit the CDC, don't imply endorsement, link to the source. Logos may not be used
  without permission, and most releases use the CDC logo as `og:image`, so URLs that look like
  logos are dropped. Third-party pictures on CDC pages keep their own rights.
- **ACSM**: no published syndication licence found. Headline, link and an original summary are
  ordinary linking practice; images off; member-only items skipped.
- **WHO, Nature Medicine** (disabled): images off if enabled.
- The summaries are machine-written. The app should say so near the list ("Summaries written
  automatically from the publisher's description") and keep the wellness framing: they report,
  they don't advise.

## Tests

```bash
cd supabase/functions && deno test --allow-read && deno check news-ingest/index.ts
# without Deno: supabase/scripts/test-functions.sh (runs every function's tests under Bun)
```

Deno is not installed on the Mac this was written on, so neither command was run here. What
was run instead on 2026-10-03: the 24 tests under Bun with a stand-in for `Deno.test` and
`@std/assert` (all pass), a strict `tsc` check of every file with Deno's globals declared (no
error), the parser against the live feeds (every enabled feed parsed, 62 recent items, the CDC
redirect resolved and its logo image dropped), and the migration on a scratch Postgres 17 with
stand-ins for cron, net and Vault: RLS hides a 61-day-old row from `anon` and `authenticated`,
`anon` can't insert or call the tick, the checks refuse an unknown topic, an `http` link, an
empty topic list and a duplicate link, and the tick skips without a Vault secret and posts the
right URL, bearer and timeout with one.

## Sources

- Foundry chat models, endpoint, `api-key` header, `model` = deployment name:
  https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure
- Region availability:
  https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability
- ScienceDaily terms: https://www.sciencedaily.com/terms.htm
- CDC reuse policy: https://www.cdc.gov/other/agencymaterials.html
