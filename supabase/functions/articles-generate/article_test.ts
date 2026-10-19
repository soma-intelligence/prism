// deno test --allow-read (or supabase/scripts/test-functions.sh, which runs these under Bun).
import { assert, assertEquals } from "jsr:@std/assert@1";
import { buildMessages, buildRow, coverFor, groupByTopic, longestSharedRun, type NewsItem, parseDraft, slugFor, undash, wordCount } from "./article.ts";
import { DEFAULT_MODEL, readConfig, run, type Store } from "./index.ts";

const item = (id: string, topics: string[], day: number, source = "ScienceDaily", image: string | null = null): NewsItem => ({
  id,
  source_name: source,
  source_url: `https://example.test/${id}`,
  title: `Study ${id} looks at evening light and how people sleep`,
  summary: `Researchers followed a group of adults for several weeks and measured sleep timing against evening light exposure in item ${id}.`,
  topics,
  image_url: image,
  published_at: `2026-10-0${day}T08:00:00Z`,
});

// A body of `n` words that copies nothing and names its source.
function body(n: number): string {
  const words = ["calm", "routine", "evening", "walk", "water", "steady", "habit", "rest", "light", "morning"];
  const out = ["## What was found", "ScienceDaily reports"];
  for (let i = 0; out.join(" ").split(/\s+/).length < n; i++) out.push(words[(i * 7) % words.length] + (i % 9 === 8 ? "." : ""));
  return out.join(" ");
}

const draft = (n = 500, extra = "") => JSON.stringify({ title: "Evening light and sleep timing", subtitle: "What a few new studies suggest about light after dark.", body: body(n) + extra });

Deno.test("groups news by article topic, newest first, without reusing items", () => {
  const items = [item("a", ["sleep"], 1), item("b", ["sleep", "mind"], 3), item("c", ["sleep"], 2), item("d", ["mind"], 2), item("e", ["research"], 2)];
  const groups = groupByTopic(items, new Set(["c"]), 2, 5);
  assertEquals([...groups.keys()], ["sleep"]);
  assertEquals(groups.get("sleep")!.map((i) => i.id), ["b", "a"]);
});

Deno.test("an accepted draft becomes a row with sources, minutes and no cover from a source that forbids images", () => {
  const items = [item("a", ["sleep"], 1, "ScienceDaily", "https://img.test/a.jpg"), item("b", ["sleep"], 2, "CDC", "https://img.test/b.jpg")];
  const checked = parseDraft(draft(), items);
  assert(checked.ok, checked.ok ? "" : checked.reason);
  const row = buildRow("sleep", checked.value, items, { model: "model-a", day: "2026-10-03", autoPublish: false, imagesAllowed: (s) => s === "CDC" });
  assertEquals(row.published, false);
  assertEquals(row.generated_by, "articles-generate");
  assertEquals(row.model, "model-a");
  assertEquals(row.sources.length, 2);
  assertEquals(row.cover_image_url, "https://img.test/b.jpg");
  assertEquals(row.cover_credit, "CDC");
  assertEquals(row.minutes, 3);
  assertEquals(row.source_news_ids, ["a", "b"]);
  assert(row.slug.startsWith("sleep-2026-10-03-evening-light"));
});

Deno.test("no source allows images: no cover, the app draws the topic gradient", () => {
  assertEquals(coverFor([item("a", ["sleep"], 1, "ScienceDaily", "https://img.test/a.jpg")], () => false).url, null);
});

Deno.test("refuses short, long, hyped, copied and unattributed drafts", () => {
  const items = [item("a", ["sleep"], 1)];
  assert(!parseDraft(draft(200), items).ok, "too short");
  assert(!parseDraft(draft(900), items).ok, "too long");
  assert(!parseDraft(draft(500, " This could cure insomnia."), items).ok, "cure");
  assert(!parseDraft(draft(500, " A breakthrough!"), items).ok, "hype");
  assert(!parseDraft(draft(500, ` ${items[0].summary}`), items).ok, "copied");
  const noSource = JSON.stringify({ title: "T", subtitle: "S", body: body(500).replace("ScienceDaily reports", "Reports say") });
  assert(!parseDraft(noSource, items).ok, "unattributed");
  assert(!parseDraft("not json", items).ok, "not json");
});

Deno.test("dashes become commas", () => {
  assertEquals(undash("light \u2014 then dark"), "light, then dark");
  assertEquals(undash("a - b"), "a, b");
});

Deno.test("word count and shared runs", () => {
  assertEquals(wordCount("## One two\n\nthree *four*"), 4);
  assertEquals(longestSharedRun("the quick brown fox jumps", ["a quick brown fox runs"]), 3);
  assertEquals(slugFor("mind", "Calm: a ten minute walk!", "2026-10-03"), "mind-2026-10-03-calm-a-ten-minute-walk");
});

Deno.test("a retry carries the refusal reason", () => {
  const messages = buildMessages("sleep", [item("a", ["sleep"], 1)], "the body has 120 words");
  assertEquals(messages.length, 3);
  assert(messages[2].content.includes("120 words"));
  assert(messages[0].content.includes("Never diagnose"));
});

Deno.test("config defaults to the default deployment and drafts, never auto publish", () => {
  const conf = readConfig((n) => ({ FOUNDRY_ENDPOINT: "https://r.openai.azure.com", FOUNDRY_API_KEY: "k", SUPABASE_URL: "https://p.supabase.co", SUPABASE_SERVICE_ROLE_KEY: "s" } as Record<string, string>)[n]);
  assert(conf.ok);
  assertEquals(conf.cfg.model, DEFAULT_MODEL);
  assertEquals(conf.cfg.model, "grok-4.6");
  assertEquals(conf.cfg.autoPublish, false);
});

Deno.test("a run writes one article per topic, retries a refused draft once, and stores drafts", async () => {
  const stored: unknown[] = [];
  const store: Store = {
    recentNews: () => Promise.resolve([item("a", ["sleep"], 1), item("b", ["sleep"], 2), item("c", ["sleep"], 3), item("d", ["mind"], 3)]),
    usedNewsIds: () => Promise.resolve(new Set()),
    insert: (row) => {
      stored.push(row);
      return Promise.resolve(true);
    },
  };
  const replies = [draft(100), draft()];
  const report = await run(
    { endpoint: "e", apiKey: "k", model: "model-a", supabaseUrl: "u", serviceKey: "s", autoPublish: false, windowDays: 7, minItems: 3, maxPerRun: 3 },
    store,
    () => Promise.resolve({ text: replies.shift()!, promptTokens: 900, completionTokens: 800 }),
    { dryRun: false, maxArticles: 3, now: new Date("2026-10-04T05:23:00Z") },
  );
  assertEquals(report.topics, ["sleep"]);
  assertEquals(report.stored, 1);
  assertEquals(report.promptTokens, 1800);
  assertEquals((stored[0] as { published: boolean }).published, false);
});
