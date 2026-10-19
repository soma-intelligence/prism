// The curated feeds news-ingest reads. To add or remove one, edit this list and redeploy
// (README.md, "Feeds"). Every URL here answered 200 with a valid, current feed on 2026-10-03.
//
// images: whether the source's terms let the app hotlink its og:image or feed media. When
//   false, image_url stays null for that source.
// linkMustInclude: keep only items whose link contains this (ScienceDaily allows reuse of
//   headlines only for /releases/ stories).
// skipCategories: drop items carrying one of these feed categories (case-insensitive).
// enabled: false keeps a vetted feed in the list without reading it.

export interface Feed {
  id: string;
  sourceName: string;
  url: string;
  images: boolean;
  enabled: boolean;
  linkMustInclude?: string;
  skipCategories?: string[];
}

export const FEEDS: Feed[] = [
  {
    id: "sciencedaily-health",
    sourceName: "ScienceDaily",
    url: "https://www.sciencedaily.com/rss/health_medicine.xml",
    images: false,
    enabled: true,
    linkMustInclude: "/releases/",
  },
  {
    id: "sciencedaily-sleep",
    sourceName: "ScienceDaily",
    url: "https://www.sciencedaily.com/rss/mind_brain/sleep_disorders.xml",
    images: false,
    enabled: true,
    linkMustInclude: "/releases/",
  },
  {
    id: "sciencedaily-fitness",
    sourceName: "ScienceDaily",
    url: "https://www.sciencedaily.com/rss/health_medicine/fitness.xml",
    images: false,
    enabled: true,
    linkMustInclude: "/releases/",
  },
  {
    id: "sciencedaily-nutrition",
    sourceName: "ScienceDaily",
    url: "https://www.sciencedaily.com/rss/health_medicine/nutrition.xml",
    images: false,
    enabled: true,
    linkMustInclude: "/releases/",
  },
  {
    id: "sciencedaily-heart",
    sourceName: "ScienceDaily",
    url: "https://www.sciencedaily.com/rss/health_medicine/heart_disease.xml",
    images: false,
    enabled: true,
    linkMustInclude: "/releases/",
  },
  {
    id: "sciencedaily-aging",
    sourceName: "ScienceDaily",
    url: "https://www.sciencedaily.com/rss/health_medicine/healthy_aging.xml",
    images: false,
    enabled: true,
    linkMustInclude: "/releases/",
  },
  {
    id: "sciencedaily-mental-health",
    sourceName: "ScienceDaily",
    url: "https://www.sciencedaily.com/rss/mind_brain/mental_health.xml",
    images: false,
    enabled: true,
    linkMustInclude: "/releases/",
  },
  {
    // US government work, public domain apart from logos and third-party pictures; the logo
    // filter in parse.ts drops the CDC logo most releases use as og:image.
    id: "cdc-newsroom",
    sourceName: "CDC",
    url: "https://tools.cdc.gov/api/v2/resources/media/132608.rss",
    images: true,
    enabled: true,
  },
  {
    id: "acsm",
    sourceName: "American College of Sports Medicine",
    url: "https://www.acsm.org/rss",
    images: false,
    enabled: true,
    skipCategories: ["Member Exclusive"],
  },
  {
    // Valid feed but its newest item was 2026-02-25 on 2026-10-03. Enable if it wakes up.
    id: "who-news",
    sourceName: "World Health Organization",
    url: "https://www.who.int/rss-feeds/news-english.xml",
    images: false,
    enabled: false,
  },
  {
    // Clinical research journal, current. Off by default: mostly trials and treatments,
    // far from wellness reading.
    id: "nature-medicine",
    sourceName: "Nature Medicine",
    url: "https://www.nature.com/nm.rss",
    images: false,
    enabled: false,
  },
];
