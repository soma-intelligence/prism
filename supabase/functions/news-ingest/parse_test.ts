// deno test --allow-read functions/news-ingest/
import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  decodeEntities,
  isLikelyLogo,
  normalizeUrl,
  parseDate,
  parseFeed,
  parsePageMeta,
  pickCandidates,
  stripHtml,
} from "./parse.ts";

const fixture = (name: string) => Deno.readTextFileSync(new URL(`./fixtures/${name}`, import.meta.url));

Deno.test("decodeEntities handles named, decimal and hex entities", () => {
  assertEquals(decodeEntities("A &amp; B &#124; C &#x2019; &hellip; &bogus;"), "A & B | C \u2019 \u2026 &bogus;");
});

Deno.test("stripHtml drops markup and collapses space", () => {
  assertEquals(stripHtml("<p>One <strong>two</strong></p>\n<p>three</p><script>x()</script>"), "One two three");
});

Deno.test("normalizeUrl upgrades http, drops fragments and tracking, refuses other schemes", () => {
  assertEquals(
    normalizeUrl("http://example.org/a?utm_source=rss&id=3#top"),
    "https://example.org/a?id=3",
  );
  assertEquals(normalizeUrl("/x", "https://example.org/feed"), "https://example.org/x");
  assertEquals(normalizeUrl("javascript:alert(1)"), null);
  assertEquals(normalizeUrl("not a url"), null);
});

Deno.test("parseDate reads RFC 822 with zone names and ISO 8601", () => {
  assertEquals(parseDate("Fri, 02 Oct 2026 09:46:53 EDT")?.toISOString(), "2026-10-02T13:46:53.000Z");
  assertEquals(parseDate("Wed, 25 Feb 2026 18:06:55 Z")?.toISOString(), "2026-02-25T18:06:55.000Z");
  assertEquals(parseDate("2026-10-02T09:00:00Z")?.toISOString(), "2026-10-02T09:00:00.000Z");
  assertEquals(parseDate("soon"), null);
});

Deno.test("parseFeed reads the ScienceDaily shape", () => {
  const items = parseFeed(fixture("sciencedaily.xml"), "https://www.sciencedaily.com/rss/health_medicine.xml");
  // The item without a title is dropped.
  assertEquals(items.length, 4);
  assertEquals(items[0].title, "Evening light linked to later sleep in a small study");
  assertEquals(items[0].link, "https://www.sciencedaily.com/releases/2026/10/261002000001.htm");
  assert(items[0].excerpt.startsWith("Researchers followed 120 adults"));
  assertEquals(items[0].publishedAt?.toISOString(), "2026-10-02T13:46:53.000Z");
  assertEquals(items[0].imageUrl, null);
  assertEquals(items[1].title, "Walking breaks & blood sugar: what a lab trial saw");
  assertEquals(items[1].link, "https://www.sciencedaily.com/releases/2026/10/261001000002.htm");
});

Deno.test("parseFeed reads CDC media:content, enclosures and categories", () => {
  const items = parseFeed(fixture("cdc.xml"), "https://tools.cdc.gov/api/v2/resources/media/132608.rss");
  assertEquals(items.length, 2);
  assertEquals(items[0].link, "https://tools.cdc.gov/api/embed/downloader/download.asp?m=132608&c=900001");
  assertEquals(items[0].imageUrl, "https://www.cdc.gov/media/media/images/2024/09/cdc-logo.jpg");
  assertEquals(items[1].imageUrl, "https://www.cdc.gov/media/images/sleep-survey.png");
  assertEquals(items[1].categories, ["CDC Newsroom", "What's New"]);
});

Deno.test("parseFeed never takes content:encoded, and reads CDATA categories", () => {
  const items = parseFeed(fixture("acsm.xml"), "https://www.acsm.org/rss");
  assertEquals(items.length, 2);
  assertEquals(items[0].title, "Science Spotlight | Late September 2026");
  assertEquals(items[0].categories, ["Member Exclusive", "physical activity"]);
  for (const item of items) assert(!item.excerpt.includes("FULL ARTICLE TEXT"));
  assert(items[1].excerpt.startsWith("An overview of how resistance training fits"));
});

Deno.test("parseFeed reads Atom: alternate link, escaped HTML, summary not content", () => {
  const items = parseFeed(fixture("atom.xml"), "https://news.example.org/feed.atom");
  assertEquals(items.length, 2);
  assertEquals(items[0].title, "Hydration and focus \u2014 a pilot study");
  assertEquals(items[0].link, "https://news.example.org/2026/10/hydration-focus");
  assertEquals(items[0].excerpt, "A pilot study of 40 students looked at water intake and attention tests.");
  assertEquals(items[0].imageUrl, "https://news.example.org/img/thumb.jpg");
  assertEquals(items[0].categories, ["nutrition"]);
  assertEquals(items[1].publishedAt, null);
});

Deno.test("parsePageMeta reads og tags in either attribute order and prefers og:url", () => {
  const meta = parsePageMeta(fixture("article.html"), "https://www.cdc.gov/media/releases/2026/physical-activity-adults.html");
  assertEquals(meta.canonicalUrl, "https://www.cdc.gov/media/releases/2026/physical-activity-adults.html");
  assertEquals(meta.imageUrl, "https://www.cdc.gov/media/images/2026/activity.jpg?_=1");
  assertEquals(meta.description, "Survey data on how many adults meet activity guidelines & how that changed.");
});

Deno.test("isLikelyLogo spots logos and placeholders", () => {
  assert(isLikelyLogo("https://www.cdc.gov/media/media/images/2024/09/cdc-logo.jpg"));
  assert(isLikelyLogo("https://example.org/img/default-share.png"));
  assert(!isLikelyLogo("https://www.cdc.gov/media/images/2026/activity.jpg"));
});

Deno.test("pickCandidates filters by age, rules and known links, then takes round-robin", () => {
  const now = new Date("2026-10-03T12:00:00Z");
  const sd = parseFeed(fixture("sciencedaily.xml"), "https://www.sciencedaily.com/rss/health_medicine.xml");
  const acsm = parseFeed(fixture("acsm.xml"), "https://www.acsm.org/rss");
  const cdc = parseFeed(fixture("cdc.xml"), "https://tools.cdc.gov/api/v2/resources/media/132608.rss");
  const byFeed = [
    { feedId: "sd", sourceName: "ScienceDaily", items: sd },
    { feedId: "acsm", sourceName: "ACSM", items: acsm },
    { feedId: "cdc", sourceName: "CDC", items: cdc },
  ];
  const picked = pickCandidates(byFeed, {
    now,
    maxAgeDays: 14,
    perFeedCap: 1,
    totalCap: 10,
    known: new Set(["https://www.sciencedaily.com/releases/2026/10/261002000001.htm"]),
    linkMustInclude: { sd: "/releases/" },
    skipCategories: { acsm: ["member exclusive"] },
  });
  assertEquals(picked.map((c) => c.link), [
    // Newest sd item is known; the video is not a release; June is too old.
    "https://www.sciencedaily.com/releases/2026/10/261001000002.htm",
    // The member-only item is skipped.
    "https://acsm.org/strength-training-basics-older-adults/",
    // perFeedCap 1: only the newest CDC item.
    "https://tools.cdc.gov/api/embed/downloader/download.asp?m=132608&c=900001",
  ]);
  assertEquals(picked[0].sourceName, "ScienceDaily");

  const capped = pickCandidates(byFeed, { now, maxAgeDays: 14, perFeedCap: 5, totalCap: 2, known: new Set() });
  assertEquals(capped.length, 2);
  // Round-robin: one from each of the first two feeds, not two from the first.
  assertEquals(capped.map((c) => c.feedId), ["sd", "acsm"]);
});

Deno.test("pickCandidates drops a link listed by two feeds", () => {
  const now = new Date("2026-10-03T12:00:00Z");
  const sd = parseFeed(fixture("sciencedaily.xml"), "https://www.sciencedaily.com/rss/health_medicine.xml");
  const picked = pickCandidates(
    [
      { feedId: "a", sourceName: "ScienceDaily", items: sd },
      { feedId: "b", sourceName: "ScienceDaily", items: sd },
    ],
    { now, maxAgeDays: 14, perFeedCap: 10, totalCap: 10, known: new Set() },
  );
  const links = picked.map((c) => c.link);
  assertEquals(links.length, new Set(links).size);
});
