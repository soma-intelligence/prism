// articles-generate: once a day, one original Explore article per topic from
// the last days' news_items, written by a chat deployment on Azure AI
// Foundry and stored in app_articles as drafts for review before release.
//
// POST with the service role bearer (pg_cron does it through
// articles_generate_tick). Body, all optional: {"dryRun": true} returns the
// drafts without storing them; {"wait": true} answers when the run is done;
// {"maxArticles": n} caps this run.
//
// Environment (function secrets):
//   FOUNDRY_ARTICLE_ENDPOINT  defaults to FOUNDRY_ENDPOINT
//   FOUNDRY_ARTICLE_API_KEY   defaults to FOUNDRY_API_KEY
//   FOUNDRY_ARTICLE_MODEL     deployment name, default DEFAULT_MODEL below
//   ARTICLES_AUTO_PUBLISH     "true" publishes at once; anything else keeps drafts
//   ARTICLES_WINDOW_DAYS      news this recent (default 7)
//   ARTICLES_MIN_ITEMS        news items a topic needs (default 3)
//   ARTICLES_MAX_PER_RUN      articles per run (default 3)
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  set by Supabase

import { chat } from "../_shared/foundry.ts";
import { fetchJson, log, withRetries } from "../_shared/http.ts";
import { bearer, json, restHeaders, sameSecret } from "../_shared/respond.ts";
import { FEEDS } from "../news-ingest/feeds.ts";
import { type ArticleRow, buildMessages, buildRow, groupByTopic, type NewsItem, parseDraft } from "./article.ts";

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void } | undefined;

export const DEFAULT_MODEL = "grok-4.6";

export interface Config {
  endpoint: string;
  apiKey: string;
  model: string;
  supabaseUrl: string;
  serviceKey: string;
  autoPublish: boolean;
  windowDays: number;
  minItems: number;
  maxPerRun: number;
}

export function readConfig(env: (name: string) => string | undefined): { ok: true; cfg: Config } | { ok: false; missing: string[] } {
  const endpoint = env("FOUNDRY_ARTICLE_ENDPOINT") ?? env("FOUNDRY_ENDPOINT");
  const apiKey = env("FOUNDRY_ARTICLE_API_KEY") ?? env("FOUNDRY_API_KEY");
  const missing = [
    endpoint ? null : "FOUNDRY_ARTICLE_ENDPOINT",
    apiKey ? null : "FOUNDRY_ARTICLE_API_KEY",
    env("SUPABASE_URL") ? null : "SUPABASE_URL",
    env("SUPABASE_SERVICE_ROLE_KEY") ? null : "SUPABASE_SERVICE_ROLE_KEY",
  ].filter((n): n is string => n !== null);
  if (missing.length > 0) return { ok: false, missing };
  const num = (name: string, fallback: number, max: number) => {
    const n = Number(env(name));
    return Number.isFinite(n) && n > 0 ? Math.min(Math.floor(n), max) : fallback;
  };
  return {
    ok: true,
    cfg: {
      endpoint: endpoint!,
      apiKey: apiKey!,
      model: env("FOUNDRY_ARTICLE_MODEL") || DEFAULT_MODEL,
      supabaseUrl: env("SUPABASE_URL")!,
      serviceKey: env("SUPABASE_SERVICE_ROLE_KEY")!,
      autoPublish: env("ARTICLES_AUTO_PUBLISH") === "true",
      windowDays: num("ARTICLES_WINDOW_DAYS", 7, 30),
      minItems: num("ARTICLES_MIN_ITEMS", 3, 10),
      maxPerRun: num("ARTICLES_MAX_PER_RUN", 3, 7),
    },
  };
}

// What the run reads and writes, so a test can hand it fakes.
export interface Store {
  recentNews(sinceIso: string): Promise<NewsItem[]>;
  usedNewsIds(): Promise<Set<string>>;
  insert(row: ArticleRow): Promise<boolean>;
}

export type Writer = (messages: ReturnType<typeof buildMessages>) => Promise<{ text: string; promptTokens: number; completionTokens: number }>;

export function createStore(supabaseUrl: string, serviceKey: string): Store {
  const base = `${supabaseUrl.replace(/\/+$/, "")}/rest/v1`;
  const headers = restHeaders(serviceKey);
  return {
    async recentNews(sinceIso) {
      const q = `select=id,source_name,source_url,title,summary,topics,image_url,published_at&published_at=gte.${encodeURIComponent(sinceIso)}&order=published_at.desc&limit=200`;
      return (await withRetries("news-select", 3, () => fetchJson(`${base}/news_items?${q}`, { headers, timeoutMs: 10_000 }))) as NewsItem[];
    },
    async usedNewsIds() {
      const q = `select=source_news_ids&generated_by=eq.articles-generate&order=created_at.desc&limit=200`;
      const rows = (await withRetries("articles-select", 3, () => fetchJson(`${base}/app_articles?${q}`, { headers, timeoutMs: 10_000 }))) as { source_news_ids: string[] }[];
      return new Set(rows.flatMap((r) => r.source_news_ids ?? []));
    },
    async insert(row) {
      const rows = (await withRetries("articles-insert", 3, () =>
        fetchJson(`${base}/app_articles?on_conflict=slug`, {
          method: "POST",
          headers: { ...headers, Prefer: "resolution=ignore-duplicates,return=representation" },
          body: JSON.stringify([row]),
          timeoutMs: 10_000,
        }))) as unknown[];
      return Array.isArray(rows) && rows.length > 0;
    },
  };
}

export interface Report {
  topics: string[];
  stored: number;
  refused: number;
  failed: number;
  promptTokens: number;
  completionTokens: number;
  drafts?: ArticleRow[];
}

const imagesAllowed = (sourceName: string) => FEEDS.some((f) => f.sourceName === sourceName && f.images);

export async function run(cfg: Config, store: Store, write: Writer, opts: { dryRun: boolean; maxArticles: number; now: Date }): Promise<Report> {
  const since = new Date(opts.now.getTime() - cfg.windowDays * 86_400_000).toISOString();
  const [news, used] = await Promise.all([store.recentNews(since), store.usedNewsIds()]);
  const groups = [...groupByTopic(news, used, cfg.minItems, 5)].slice(0, opts.maxArticles);
  const report: Report = { topics: groups.map(([t]) => t), stored: 0, refused: 0, failed: 0, promptTokens: 0, completionTokens: 0 };
  if (opts.dryRun) report.drafts = [];
  const day = opts.now.toISOString().slice(0, 10);

  for (const [topic, items] of groups) {
    try {
      let reason: string | undefined;
      let row: ArticleRow | null = null;
      for (let attempt = 0; attempt < 2 && !row; attempt++) {
        const reply = await write(buildMessages(topic, items, reason));
        report.promptTokens += reply.promptTokens;
        report.completionTokens += reply.completionTokens;
        const checked = parseDraft(reply.text, items);
        if (checked.ok) {
          row = buildRow(topic, checked.value, items, { model: cfg.model, day, autoPublish: cfg.autoPublish, imagesAllowed });
        } else {
          reason = checked.reason;
          log("warn", "article_refused", { topic, attempt, reason });
        }
      }
      if (!row) {
        report.refused++;
        continue;
      }
      if (opts.dryRun) {
        report.drafts!.push(row);
        continue;
      }
      if (await store.insert(row)) {
        report.stored++;
        log("info", "article_stored", { topic, slug: row.slug, published: row.published, sources: row.source_news_ids.length });
      }
    } catch (err) {
      report.failed++;
      log("error", "article_failed", { topic, error: String(err) });
    }
  }
  log("info", "run_finished", { ...report, drafts: undefined });
  return report;
}

if (import.meta.main) {
  Deno.serve(async (req) => {
    if (req.method !== "POST") return json(405, { error: "POST only" });
    const conf = readConfig((n) => Deno.env.get(n));
    if (!conf.ok) {
      log("error", "config_missing", { missing: conf.missing });
      return json(500, { error: "function not configured", missing: conf.missing });
    }
    const cfg = conf.cfg;
    const token = bearer(req);
    if (!token || !sameSecret(token, cfg.serviceKey)) return json(401, { error: "unauthorized" });
    let body: { dryRun?: unknown; wait?: unknown; maxArticles?: unknown } = {};
    try {
      body = await req.json();
    } catch {
      // An empty body is fine.
    }
    const maxArticles = typeof body.maxArticles === "number" && body.maxArticles > 0 ? Math.min(Math.floor(body.maxArticles), cfg.maxPerRun) : cfg.maxPerRun;
    const writer: Writer = (messages) =>
      chat({ endpoint: cfg.endpoint, apiKey: cfg.apiKey, model: cfg.model, timeoutMs: 90_000, attempts: 3, temperature: 0.5, maxTokens: 1600 }, messages);
    const task = run(cfg, createStore(cfg.supabaseUrl, cfg.serviceKey), writer, { dryRun: body.dryRun === true, maxArticles, now: new Date() });
    if (body.wait === true) {
      try {
        return json(200, await task);
      } catch (err) {
        return json(500, { error: String(err) });
      }
    }
    if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(task.catch(() => {}));
    else task.catch(() => {});
    return json(202, { started: true, maxArticles });
  });
}
