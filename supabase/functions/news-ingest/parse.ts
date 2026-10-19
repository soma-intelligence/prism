// Feed and page parsing for news-ingest. Pure functions, no network: tested by parse_test.ts
// against the fixtures. Reads RSS 2.0 and Atom with a small tag scanner, which is enough for
// the curated feeds and keeps the function free of an XML dependency.

export interface FeedItem {
  title: string;
  link: string;
  excerpt: string;
  publishedAt: Date | null;
  imageUrl: string | null;
  categories: string[];
}

const NAMED_ENTITIES: Record<string, string> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " ",
  hellip: "\u2026",
  rsquo: "\u2019",
  lsquo: "\u2018",
  rdquo: "\u201d",
  ldquo: "\u201c",
  ndash: "\u2013",
  mdash: "\u2014",
};

export function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (whole, code: string) => {
    if (code[0] === "#") {
      const n = code[1] === "x" || code[1] === "X" ? parseInt(code.slice(2), 16) : parseInt(code.slice(1), 10);
      return Number.isFinite(n) && n > 0 && n <= 0x10ffff ? String.fromCodePoint(n) : whole;
    }
    return NAMED_ENTITIES[code.toLowerCase()] ?? whole;
  });
}

function unwrapCdata(s: string): string {
  return s.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1");
}

export function stripHtml(s: string): string {
  return decodeEntities(
    s
      .replace(/<(script|style)[\s\S]*?<\/\1>/gi, " ")
      .replace(/<br\s*\/?>/gi, " ")
      .replace(/<\/p>/gi, " ")
      .replace(/<[^>]+>/g, " "),
  )
    .replace(/\s+/g, " ")
    .trim();
}

function escapeTag(tag: string): string {
  return tag.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// Inner text of every <tag ...>...</tag> in block, CDATA unwrapped, entities and markup left.
function rawBlocks(block: string, tag: string): string[] {
  const t = escapeTag(tag);
  const re = new RegExp(`<${t}(?:\\s[^>]*)?>([\\s\\S]*?)</${t}>`, "gi");
  return [...block.matchAll(re)].map((m) => unwrapCdata(m[1]));
}

// Opening (or self-closing) tags named tag, whole, for reading attributes.
function openTags(block: string, tag: string): string[] {
  const t = escapeTag(tag);
  const re = new RegExp(`<${t}(?:\\s[^>]*)?/?>`, "gi");
  return [...block.matchAll(re)].map((m) => m[0]);
}

function textOf(block: string, ...tags: string[]): string {
  for (const tag of tags) {
    const found = rawBlocks(block, tag)[0];
    if (found !== undefined) {
      // Decoded before stripping: feeds often escape their HTML (&lt;p&gt;).
      const text = stripHtml(decodeEntities(found));
      if (text) return text;
    }
  }
  return "";
}

export function attrOf(tag: string, name: string): string | null {
  const re = new RegExp(`\\s${escapeTag(name)}\\s*=\\s*("([^"]*)"|'([^']*)')`, "i");
  const m = tag.match(re);
  if (!m) return null;
  return decodeEntities(m[2] ?? m[3] ?? "").trim();
}

export function parseDate(s: string): Date | null {
  const trimmed = s.trim();
  if (!trimmed) return null;
  // RFC 822 "Z" and "UT" suffixes, which some engines refuse.
  const fixed = trimmed.replace(/\s(UT|Z)$/i, " GMT");
  const t = Date.parse(fixed);
  return Number.isNaN(t) ? null : new Date(t);
}

const TRACKING_PARAMS = /^(utm_[a-z]+|fbclid|gclid|mc_cid|mc_eid|ref)$/i;

// An absolute https URL without fragment or tracking parameters, or null. http is upgraded.
export function normalizeUrl(raw: string, base?: string): string | null {
  let url: URL;
  try {
    url = new URL(raw.trim(), base);
  } catch {
    return null;
  }
  if (url.protocol === "http:") url.protocol = "https:";
  if (url.protocol !== "https:") return null;
  url.hash = "";
  for (const key of [...url.searchParams.keys()]) {
    if (TRACKING_PARAMS.test(key)) url.searchParams.delete(key);
  }
  const out = url.toString();
  return out.length <= 2000 ? out : null;
}

const IMAGE_EXT = /\.(jpe?g|png|webp|gif|avif)(\?|$)/i;

function itemImage(block: string, base: string): string | null {
  for (const tag of [...openTags(block, "media:content"), ...openTags(block, "media:thumbnail")]) {
    const url = attrOf(tag, "url");
    const type = attrOf(tag, "type") ?? "";
    const medium = attrOf(tag, "medium") ?? "";
    if (url && (type.startsWith("image/") || medium === "image" || IMAGE_EXT.test(url) || tag.startsWith("<media:thumbnail"))) {
      const n = normalizeUrl(url, base);
      if (n) return n;
    }
  }
  for (const tag of openTags(block, "enclosure")) {
    const url = attrOf(tag, "url");
    if (url && (attrOf(tag, "type") ?? "").startsWith("image/")) {
      const n = normalizeUrl(url, base);
      if (n) return n;
    }
  }
  return null;
}

function parseRssItem(block: string, base: string): FeedItem | null {
  const title = textOf(block, "title");
  let link = textOf(block, "link");
  if (!link) {
    const guidTag = openTags(block, "guid")[0] ?? "";
    if (attrOf(guidTag, "isPermaLink") !== "false") link = textOf(block, "guid");
  }
  const normalized = link ? normalizeUrl(link, base) : null;
  if (!title || !normalized) return null;
  return {
    title,
    link: normalized,
    excerpt: textOf(block, "description", "summary"),
    publishedAt: parseDate(textOf(block, "pubDate", "dc:date", "published", "updated")),
    imageUrl: itemImage(block, base),
    categories: rawBlocks(block, "category").map((c) => stripHtml(decodeEntities(c))).filter(Boolean),
  };
}

function parseAtomEntry(block: string, base: string): FeedItem | null {
  const title = textOf(block, "title");
  const links = openTags(block, "link");
  const alternate = links.find((l) => (attrOf(l, "rel") ?? "alternate") === "alternate");
  const href = alternate ? attrOf(alternate, "href") : null;
  const normalized = href ? normalizeUrl(href, base) : null;
  if (!title || !normalized) return null;
  return {
    title,
    link: normalized,
    // summary only: content may hold the whole article, which is never used.
    excerpt: textOf(block, "summary"),
    publishedAt: parseDate(textOf(block, "published", "updated")),
    imageUrl: itemImage(block, base),
    categories: openTags(block, "category")
      .map((c) => attrOf(c, "term") ?? "")
      .filter(Boolean),
  };
}

// Items of an RSS 2.0 or Atom document, in document order. Items without a title or a usable
// link are dropped.
export function parseFeed(xml: string, feedUrl: string): FeedItem[] {
  const isAtom = /<feed[\s>]/i.test(xml.slice(0, 2000)) && !/<rss[\s>]/i.test(xml.slice(0, 2000));
  const itemRe = isAtom ? /<entry(?:\s[^>]*)?>([\s\S]*?)<\/entry>/gi : /<item(?:\s[^>]*)?>([\s\S]*?)<\/item>/gi;
  const parse = isAtom ? parseAtomEntry : parseRssItem;
  const items: FeedItem[] = [];
  for (const m of xml.matchAll(itemRe)) {
    const item = parse(m[1], feedUrl);
    if (item) items.push(item);
  }
  return items;
}

// What an article page says about itself in its <head>: canonical URL, share image,
// description. Only meta tags are read, never the article's body.
export interface PageMeta {
  canonicalUrl: string | null;
  imageUrl: string | null;
  description: string;
}

// The content of the first key present, keys in order of preference.
function metaContent(html: string, keys: string[]): string | null {
  const found = new Map<string, string>();
  for (const tag of html.match(/<meta\s[^>]*>/gi) ?? []) {
    const key = (attrOf(tag, "property") ?? attrOf(tag, "name") ?? "").toLowerCase();
    const content = attrOf(tag, "content");
    if (content && !found.has(key)) found.set(key, content);
  }
  for (const key of keys) {
    const content = found.get(key);
    if (content) return content;
  }
  return null;
}

export function parsePageMeta(html: string, pageUrl: string): PageMeta {
  const head = html.slice(0, 300_000);
  const og = metaContent(head, ["og:url"]);
  const canonicalTag = (head.match(/<link\s[^>]*>/gi) ?? []).find((l) => (attrOf(l, "rel") ?? "").toLowerCase() === "canonical");
  const canonicalRaw = og ?? (canonicalTag ? attrOf(canonicalTag, "href") : null);
  const imageRaw = metaContent(head, ["og:image:secure_url", "og:image", "twitter:image", "twitter:image:src"]);
  return {
    canonicalUrl: canonicalRaw ? normalizeUrl(canonicalRaw, pageUrl) : null,
    imageUrl: imageRaw ? normalizeUrl(imageRaw, pageUrl) : null,
    description: stripHtml(metaContent(head, ["og:description", "description", "twitter:description"]) ?? ""),
  };
}

// Agency logos and stock placeholders make poor news pictures, and some (the CDC's) may not be
// reused at all.
export function isLikelyLogo(url: string): boolean {
  return /logo|favicon|placeholder|default[-_]?(image|share|og)|social[-_]?share/i.test(new URL(url).pathname);
}

export interface Candidate extends FeedItem {
  feedId: string;
  sourceName: string;
  publishedAt: Date;
}

export interface PickOptions {
  now: Date;
  maxAgeDays: number;
  perFeedCap: number;
  totalCap: number;
  known: Set<string>;
  linkMustInclude?: Record<string, string | undefined>;
  skipCategories?: Record<string, string[] | undefined>;
}

// New items worth summarizing: recent enough, not stored yet, not seen twice in this run,
// allowed by the feed's rules. Newest first within a feed, then taken round-robin across feeds
// so one busy feed can't fill the run.
export function pickCandidates(
  byFeed: { feedId: string; sourceName: string; items: FeedItem[] }[],
  opts: PickOptions,
): Candidate[] {
  const oldest = opts.now.getTime() - opts.maxAgeDays * 86_400_000;
  const newest = opts.now.getTime() + 86_400_000;
  const seen = new Set(opts.known);
  const queues = byFeed.map(({ feedId, sourceName, items }) => {
    const must = opts.linkMustInclude?.[feedId];
    const skip = (opts.skipCategories?.[feedId] ?? []).map((c) => c.toLowerCase());
    return items
      .filter((i) => i.publishedAt !== null)
      .filter((i) => i.publishedAt!.getTime() >= oldest && i.publishedAt!.getTime() <= newest)
      .filter((i) => !must || i.link.includes(must))
      .filter((i) => !i.categories.some((c) => skip.includes(c.toLowerCase())))
      .sort((a, b) => b.publishedAt!.getTime() - a.publishedAt!.getTime())
      .map((i) => ({ ...i, feedId, sourceName, publishedAt: i.publishedAt! }));
  });
  const taken = new Map<string, number>();
  const out: Candidate[] = [];
  let progressed = true;
  while (out.length < opts.totalCap && progressed) {
    progressed = false;
    for (const q of queues) {
      while (q.length > 0) {
        const next = q.shift()!;
        if (seen.has(next.link)) continue;
        if ((taken.get(next.feedId) ?? 0) >= opts.perFeedCap) {
          q.length = 0;
          break;
        }
        seen.add(next.link);
        taken.set(next.feedId, (taken.get(next.feedId) ?? 0) + 1);
        out.push(next);
        progressed = true;
        break;
      }
      if (out.length >= opts.totalCap) break;
    }
  }
  return out;
}
