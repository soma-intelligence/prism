// news-ingest: reads the curated health and wellness feeds (feeds.ts), keeps the items not yet
// in public.news_items, has a chat deployment on Azure AI Foundry write a short neutral summary
// and pick topics for each, and stores headline, link, summary, topics, image URL and source
// name. Never the article's text. Called every six hours by pg_cron through pg_net
// (20261003_news_items.sql) with the service role key as bearer.
//
// POST body (all optional): {"dryRun": true} summarizes without writing, {"wait": true} answers
// with the run's report instead of 202, {"maxNew": 5} lowers the cap for this run.
//
// Env: FOUNDRY_ENDPOINT, FOUNDRY_API_KEY, FOUNDRY_MODEL (the deployment name), and
// SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (set by Supabase itself in every Edge Function).
// Optional: NEWS_MAX_NEW (default 20), NEWS_MAX_AGE_DAYS (default 14).

import { createDb, type Db } from "./db.ts";
import { FEEDS, type Feed } from "./feeds.ts";
import { chat } from "../_shared/foundry.ts";
import { fetchText, log, sleep, withRetries } from "../_shared/http.ts";
import { type Candidate, type FeedItem, isLikelyLogo, normalizeUrl, parseFeed, parsePageMeta, pickCandidates } from "./parse.ts";
import { buildMessages, type ChatMessage, parseModelReply } from "./prompt.ts";

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void } | undefined;

const FEED_CONCURRENCY = 4;
const FEED_TIMEOUT_MS = 15_000;
const FEED_MAX_BYTES = 4_000_000;
const PAGE_TIMEOUT_MS = 10_000;
const PAGE_MAX_BYTES = 300_000;
const LLM_TIMEOUT_MS = 30_000;
const LLM_ATTEMPTS = 3;
// At most one model call every 1.5 s: ~40 a minute, under the smallest Global Standard quota.
const LLM_GAP_MS = 1_500;
const PER_FEED_CAP = 4;
// Stop starting new items after this, well inside the Edge Function's wall-clock limit.
const RUN_BUDGET_MS = 120_000;

interface Config {
  foundryEndpoint: string;
  foundryApiKey: string;
  foundryModel: string;
  supabaseUrl: string;
  serviceKey: string;
  maxNew: number;
  maxAgeDays: number;
}

function readConfig(): { ok: true; cfg: Config } | { ok: false; missing: string[] } {
  const names = ["FOUNDRY_ENDPOINT", "FOUNDRY_API_KEY", "FOUNDRY_MODEL", "SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"];
  const missing = names.filter((n) => !Deno.env.get(n));
  if (missing.length > 0) return { ok: false, missing };
  const num = (name: string, fallback: number, max: number) => {
    const n = Number(Deno.env.get(name));
    return Number.isFinite(n) && n > 0 ? Math.min(Math.floor(n), max) : fallback;
  };
  return {
    ok: true,
    cfg: {
      foundryEndpoint: Deno.env.get("FOUNDRY_ENDPOINT")!,
      foundryApiKey: Deno.env.get("FOUNDRY_API_KEY")!,
      foundryModel: Deno.env.get("FOUNDRY_MODEL")!,
      supabaseUrl: Deno.env.get("SUPABASE_URL")!,
      serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      maxNew: num("NEWS_MAX_NEW", 20, 50),
      maxAgeDays: num("NEWS_MAX_AGE_DAYS", 14, 60),
    },
  };
}

interface RunOptions {
  dryRun: boolean;
  maxNew: number;
}

export interface RunReport {
  feedsRead: number;
  feedsFailed: string[];
  candidates: number;
  stored: number;
  duplicates: number;
  refused: number;
  failed: number;
  promptTokens: number;
  completionTokens: number;
  dryRun: boolean;
  preview?: { title: string; summary: string; topics: string[]; source_url: string; image_url: string | null }[];
  ms: number;
}

async function readFeeds(feeds: Feed[]): Promise<{ feed: Feed; items: FeedItem[] }[]> {
  const out: { feed: Feed; items: FeedItem[] }[] = [];
  const queue = [...feeds];
  const worker = async () => {
    for (let feed = queue.shift(); feed; feed = queue.shift()) {
      const started = Date.now();
      try {
        const { text } = await withRetries(`feed ${feed.id}`, 2, () =>
          fetchText(feed.url, {
            timeoutMs: FEED_TIMEOUT_MS,
            maxBytes: FEED_MAX_BYTES,
            accept: "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.9, */*;q=0.5",
          }));
        const items = parseFeed(text, feed.url);
        log(items.length > 0 ? "info" : "warn", "feed_read", { feed: feed.id, items: items.length, ms: Date.now() - started });
        out.push({ feed, items });
      } catch (err) {
        log("warn", "feed_failed", { feed: feed.id, error: String(err), ms: Date.now() - started });
        out.push({ feed, items: [] });
      }
    }
  };
  await Promise.all(Array.from({ length: FEED_CONCURRENCY }, worker));
  return out;
}

// The article's own address and share image, from its <head>. A failure leaves the feed's values.
async function resolvePage(c: Candidate): Promise<{ url: string; imageUrl: string | null; description: string }> {
  try {
    const { text, finalUrl } = await fetchText(c.link, {
      timeoutMs: PAGE_TIMEOUT_MS,
      maxBytes: PAGE_MAX_BYTES,
      accept: "text/html,application/xhtml+xml",
    });
    const final = normalizeUrl(finalUrl) ?? c.link;
    const meta = parsePageMeta(text, final);
    // og:url is trusted only on the host the link led to.
    const canonical = meta.canonicalUrl && new URL(meta.canonicalUrl).host === new URL(final).host ? meta.canonicalUrl : final;
    return { url: canonical, imageUrl: meta.imageUrl, description: meta.description };
  } catch (err) {
    log("warn", "page_failed", { url: c.link, error: String(err) });
    return { url: c.link, imageUrl: null, description: "" };
  }
}

async function summarize(cfg: Config, messages: ChatMessage[], report: RunReport) {
  const first = await chat(
    { endpoint: cfg.foundryEndpoint, apiKey: cfg.foundryApiKey, model: cfg.foundryModel, timeoutMs: LLM_TIMEOUT_MS, attempts: LLM_ATTEMPTS },
    messages,
  );
  report.promptTokens += first.promptTokens;
  report.completionTokens += first.completionTokens;
  const parsed = parseModelReply(first.text);
  if (parsed.ok) return parsed;
  // One second chance, told why the first answer was refused.
  await sleep(LLM_GAP_MS);
  const second = await chat(
    { endpoint: cfg.foundryEndpoint, apiKey: cfg.foundryApiKey, model: cfg.foundryModel, timeoutMs: LLM_TIMEOUT_MS, attempts: LLM_ATTEMPTS },
    [
      ...messages,
      { role: "user", content: `That answer was refused (${parsed.reason}). Answer again with one JSON object that follows every rule.` },
    ],
  );
  report.promptTokens += second.promptTokens;
  report.completionTokens += second.completionTokens;
  return parseModelReply(second.text);
}

export async function run(cfg: Config, db: Db, opts: RunOptions): Promise<RunReport> {
  const started = Date.now();
  const report: RunReport = {
    feedsRead: 0,
    feedsFailed: [],
    candidates: 0,
    stored: 0,
    duplicates: 0,
    refused: 0,
    failed: 0,
    promptTokens: 0,
    completionTokens: 0,
    dryRun: opts.dryRun,
    ms: 0,
  };
  if (opts.dryRun) report.preview = [];
  log("info", "run_started", { dryRun: opts.dryRun, maxNew: opts.maxNew, model: cfg.foundryModel });

  const feeds = FEEDS.filter((f) => f.enabled);
  const read = await readFeeds(feeds);
  report.feedsRead = read.filter((r) => r.items.length > 0).length;
  report.feedsFailed = read.filter((r) => r.items.length === 0).map((r) => r.feed.id);
  const byFeed = read.map((r) => ({ feedId: r.feed.id, sourceName: r.feed.sourceName, items: r.items }));
  const feedById = new Map(feeds.map((f) => [f.id, f]));
  const rules = {
    linkMustInclude: Object.fromEntries(feeds.map((f) => [f.id, f.linkMustInclude])),
    skipCategories: Object.fromEntries(feeds.map((f) => [f.id, f.skipCategories])),
  };
  const now = new Date();

  // Everything recent first, to ask the table which links it already holds; then the run's pick.
  const recent = pickCandidates(byFeed, { now, maxAgeDays: cfg.maxAgeDays, perFeedCap: 1000, totalCap: 5000, known: new Set(), ...rules });
  const known = await db.knownUrls(recent.map((c) => c.link));
  // Three times the cap: a redirecting link (the CDC's) may turn out to be stored already.
  const candidates = pickCandidates(byFeed, {
    now,
    maxAgeDays: cfg.maxAgeDays,
    perFeedCap: PER_FEED_CAP,
    totalCap: opts.maxNew * 3,
    known,
    ...rules,
  });
  report.candidates = candidates.length;
  log("info", "candidates", { recent: recent.length, known: known.size, picked: candidates.length });

  const seenThisRun = new Set<string>();
  let calledModel = false;
  for (const c of candidates) {
    if (report.stored >= opts.maxNew) break;
    if (Date.now() - started > RUN_BUDGET_MS) {
      log("warn", "run_budget_reached", { stored: report.stored });
      break;
    }
    const feed = feedById.get(c.feedId)!;
    try {
      const page = await resolvePage(c);
      if (page.url !== c.link && (seenThisRun.has(page.url) || (await db.knownUrls([page.url])).has(page.url))) {
        report.duplicates++;
        continue;
      }
      seenThisRun.add(page.url);

      let imageUrl: string | null = null;
      if (feed.images) {
        const raw = c.imageUrl ?? page.imageUrl;
        imageUrl = raw && !isLikelyLogo(raw) ? raw : null;
      }
      let excerpt = c.excerpt;
      if (excerpt.length < 120 && page.description && !excerpt.includes(page.description)) {
        excerpt = `${excerpt} ${page.description}`.trim();
      }

      if (calledModel) await sleep(LLM_GAP_MS);
      calledModel = true;
      const result = await summarize(cfg, buildMessages({ title: c.title, sourceName: c.sourceName, excerpt, categories: c.categories }), report);
      if (!result.ok) {
        report.refused++;
        log("warn", "summary_refused", { url: page.url, reason: result.reason });
        continue;
      }

      const row = {
        source_name: c.sourceName,
        source_url: page.url,
        title: c.title.slice(0, 300),
        summary: result.value.summary,
        topics: result.value.topics,
        image_url: imageUrl,
        published_at: c.publishedAt.toISOString(),
        model: cfg.foundryModel,
      };
      if (opts.dryRun) {
        report.preview!.push({ title: row.title, summary: row.summary, topics: row.topics, source_url: row.source_url, image_url: row.image_url });
        report.stored++;
        continue;
      }
      if (await db.insert(row)) {
        report.stored++;
        log("info", "item_stored", { url: row.source_url, feed: c.feedId, topics: row.topics });
      } else {
        report.duplicates++;
      }
    } catch (err) {
      report.failed++;
      log("error", "item_failed", { url: c.link, feed: c.feedId, error: String(err) });
    }
  }

  report.ms = Date.now() - started;
  const { preview: _preview, ...summary } = report;
  log("info", "run_finished", summary);
  return report;
}

// Constant-time comparison, so the bearer check doesn't leak the key byte by byte.
function sameSecret(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

if (import.meta.main) {
  Deno.serve(async (req) => {
    if (req.method !== "POST") return json(405, { error: "POST only" });
    const conf = readConfig();
    if (!conf.ok) {
      log("error", "config_missing", { missing: conf.missing });
      return json(500, { error: "function not configured", missing: conf.missing });
    }
    const cfg = conf.cfg;
    const bearer = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!bearer || !sameSecret(bearer, cfg.serviceKey)) {
      log("warn", "unauthorized", {});
      return json(401, { error: "unauthorized" });
    }
    let body: { dryRun?: unknown; wait?: unknown; maxNew?: unknown } = {};
    try {
      body = await req.json();
    } catch {
      // An empty body is fine.
    }
    const opts: RunOptions = {
      dryRun: body.dryRun === true,
      maxNew: typeof body.maxNew === "number" && body.maxNew > 0 ? Math.min(Math.floor(body.maxNew), cfg.maxNew) : cfg.maxNew,
    };
    const db = createDb(cfg.supabaseUrl, cfg.serviceKey);
    const task = run(cfg, db, opts).catch((err) => {
      log("error", "run_failed", { error: String(err) });
      throw err;
    });
    if (body.wait === true) {
      try {
        return json(200, await task);
      } catch (err) {
        return json(500, { error: String(err) });
      }
    }
    if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(task.catch(() => {}));
    else task.catch(() => {});
    return json(202, { started: true, dryRun: opts.dryRun, maxNew: opts.maxNew });
  });
}
