// What articles-generate asks the model and how it checks the answer. Pure
// functions, tested by article_test.ts.

import type { ChatMessage } from "../_shared/foundry.ts";

// The topics an Explore article can carry (app_articles_topic). News also has
// "research", which is not a reading topic of its own.
export const ARTICLE_TOPICS = ["sleep", "heart", "recovery", "movement", "nutrition", "mind", "longevity"] as const;
export type ArticleTopic = (typeof ARTICLE_TOPICS)[number];

export interface NewsItem {
  id: string;
  source_name: string;
  source_url: string;
  title: string;
  summary: string;
  topics: string[];
  image_url: string | null;
  published_at: string;
}

export interface Source {
  title: string;
  publisher: string;
  url: string;
}

export interface Draft {
  title: string;
  subtitle: string;
  body: string;
}

export interface ArticleRow {
  slug: string;
  title: string;
  subtitle: string;
  topic: ArticleTopic;
  minutes: number;
  cover_image_url: string | null;
  cover_credit: string | null;
  cover_credit_url: string | null;
  body: string;
  sources: Source[];
  published: boolean;
  generated_by: "articles-generate";
  model: string;
  source_news_ids: string[];
}

export const MIN_WORDS = 400;
export const MAX_WORDS = 700;

// Groups the news by article topic, newest first, leaving out items an
// earlier article already used. A topic needs `minItems` to be worth a piece;
// at most `maxItems` go into one.
export function groupByTopic(items: NewsItem[], used: Set<string>, minItems: number, maxItems: number): Map<ArticleTopic, NewsItem[]> {
  const groups = new Map<ArticleTopic, NewsItem[]>();
  const sorted = [...items].sort((a, b) => b.published_at.localeCompare(a.published_at));
  const taken = new Set<string>();
  for (const topic of ARTICLE_TOPICS) {
    const picked = sorted.filter((i) => !used.has(i.id) && !taken.has(i.id) && i.topics.includes(topic)).slice(0, maxItems);
    if (picked.length >= minItems) {
      groups.set(topic, picked);
      for (const i of picked) taken.add(i.id);
    }
  }
  return groups;
}

export const SYSTEM_PROMPT = `You write short reading pieces for Soma, a wellness app.
Write one original article from the news items you are given.

Voice: plain, calm and practical. Short sentences. Wellness wording only.
Never diagnose, never suggest a treatment, a drug, a dose or a cure. No hype, no exclamation marks.
Never copy a sentence or a phrase from the items: synthesize in your own words.
Attribute each fact to its source inline by name ("ScienceDaily reports", "according to the CDC").
Say "is associated with" when a finding is observational. Say when a study was small or in animals.
End with one short paragraph of everyday takeaways that stay within general wellness.
Do not use dashes as punctuation. Do not address medical conditions as advice.

Answer with JSON only: {"title": "...", "subtitle": "...", "body": "..."}.
title: at most 80 characters. subtitle: one sentence, at most 140 characters.
body: Markdown, ${MIN_WORDS} to ${MAX_WORDS} words, with two or three "## " headings, paragraphs, no title line, no links.`;

export function buildMessages(topic: ArticleTopic, items: NewsItem[], retryReason?: string): ChatMessage[] {
  const list = items.map((i, n) =>
    `${n + 1}. ${i.title}\n   Source: ${i.source_name}\n   Published: ${i.published_at.slice(0, 10)}\n   Summary: ${i.summary}`
  ).join("\n\n");
  const messages: ChatMessage[] = [
    { role: "system", content: SYSTEM_PROMPT },
    { role: "user", content: `Topic: ${topic}\n\nNews items:\n\n${list}` },
  ];
  if (retryReason) {
    messages.push({ role: "user", content: `Your previous answer was refused: ${retryReason}. Write it again following every rule.` });
  }
  return messages;
}

const BANNED = [
  /\bcures?\b/i, /\bcured\b/i, /\bdiagnos/i, /\btreat(s|ment|ing)?\b/i, /\bprescri/i, /\bdosage\b/i,
  /\bmiracle\b/i, /\bbreakthrough\b/i, /\bgame.?changer\b/i, /\brevolutionary\b/i, /\bguarantee/i, /!/,
];

export function wordCount(text: string): number {
  return text.replace(/[#*_`>]/g, " ").split(/\s+/).filter((w) => /[A-Za-z0-9]/.test(w)).length;
}

function words(text: string): string[] {
  return text.toLowerCase().replace(/[^a-z0-9\s]/g, " ").split(/\s+/).filter(Boolean);
}

// The longest run of words the draft shares with any source text. Eight in a
// row is a copied phrase, not a coincidence.
export function longestSharedRun(draft: string, sources: string[]): number {
  const d = words(draft);
  let best = 0;
  for (const source of sources) {
    const s = words(source);
    const index = new Map<string, number[]>();
    s.forEach((w, i) => index.set(w, [...(index.get(w) ?? []), i]));
    for (let i = 0; i < d.length; i++) {
      for (const j of index.get(d[i]) ?? []) {
        let k = 0;
        while (i + k < d.length && j + k < s.length && d[i + k] === s[j + k]) k++;
        if (k > best) best = k;
      }
    }
  }
  return best;
}

// Dashes become commas: the app's copy never uses them as punctuation.
export function undash(text: string): string {
  return text.replace(/\s*[\u2014\u2013]\s*/g, ", ").replace(/ - /g, ", ");
}

export type Checked = { ok: true; value: Draft } | { ok: false; reason: string };

export function parseDraft(reply: string, items: NewsItem[]): Checked {
  const start = reply.indexOf("{");
  const end = reply.lastIndexOf("}");
  if (start < 0 || end <= start) return { ok: false, reason: "the answer is not JSON" };
  let raw: Record<string, unknown>;
  try {
    raw = JSON.parse(reply.slice(start, end + 1));
  } catch {
    return { ok: false, reason: "the answer is not valid JSON" };
  }
  const title = typeof raw.title === "string" ? undash(raw.title.trim()) : "";
  const subtitle = typeof raw.subtitle === "string" ? undash(raw.subtitle.trim()) : "";
  const body = typeof raw.body === "string" ? undash(raw.body.trim()) : "";
  if (title.length < 1 || title.length > 120) return { ok: false, reason: "the title is missing or longer than 120 characters" };
  if (subtitle.length > 160) return { ok: false, reason: "the subtitle is longer than 160 characters" };
  const count = wordCount(body);
  if (count < MIN_WORDS || count > MAX_WORDS) return { ok: false, reason: `the body has ${count} words, not ${MIN_WORDS} to ${MAX_WORDS}` };
  const all = `${title}\n${subtitle}\n${body}`;
  const banned = BANNED.find((pattern) => pattern.test(all));
  if (banned) return { ok: false, reason: `it uses wording that is not allowed (${banned.source})` };
  const shared = longestSharedRun(all, items.flatMap((i) => [i.title, i.summary]));
  if (shared >= 8) return { ok: false, reason: `it repeats ${shared} words in a row from a source` };
  if (!items.some((i) => all.includes(i.source_name))) return { ok: false, reason: "it names none of its sources" };
  return { ok: true, value: { title, subtitle, body } };
}

export function slugFor(topic: ArticleTopic, title: string, day: string): string {
  const words = title.toLowerCase().normalize("NFKD").replace(/[^a-z0-9\s]/g, " ").split(/\s+/).filter(Boolean).slice(0, 6);
  return [topic, day, ...words].join("-").slice(0, 100).replace(/-+$/, "");
}

// The cover: the first item's image whose source allows reuse, else none, and
// the app draws the topic's gradient.
export function coverFor(items: NewsItem[], imagesAllowed: (sourceName: string) => boolean): { url: string | null; credit: string | null; creditUrl: string | null } {
  const item = items.find((i) => i.image_url && imagesAllowed(i.source_name));
  return item ? { url: item.image_url, credit: item.source_name, creditUrl: item.source_url } : { url: null, credit: null, creditUrl: null };
}

export function buildRow(
  topic: ArticleTopic,
  draft: Draft,
  items: NewsItem[],
  opts: { model: string; day: string; autoPublish: boolean; imagesAllowed: (sourceName: string) => boolean },
): ArticleRow {
  const cover = coverFor(items, opts.imagesAllowed);
  return {
    slug: slugFor(topic, draft.title, opts.day),
    title: draft.title,
    subtitle: draft.subtitle,
    topic,
    minutes: Math.max(1, Math.min(60, Math.ceil(wordCount(draft.body) / 200))),
    cover_image_url: cover.url,
    cover_credit: cover.credit,
    cover_credit_url: cover.creditUrl,
    body: draft.body,
    sources: items.slice(0, 5).map((i) => ({ title: i.title, publisher: i.source_name, url: i.source_url })),
    published: opts.autoPublish,
    generated_by: "articles-generate",
    model: opts.model,
    source_news_ids: items.map((i) => i.id),
  };
}
