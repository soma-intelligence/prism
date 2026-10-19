// public.news_items through PostgREST with the service role key. Plain fetch, so the function
// has no dependency to download.

import { fetchJson, withRetries } from "../_shared/http.ts";

export interface NewsRow {
  source_name: string;
  source_url: string;
  title: string;
  summary: string;
  topics: string[];
  image_url: string | null;
  published_at: string;
  model: string;
}

export interface Db {
  knownUrls(urls: string[]): Promise<Set<string>>;
  insert(row: NewsRow): Promise<boolean>;
}

// PostgREST's in.(...) list, each value double-quoted so commas and parentheses in a URL
// stay inside one value.
export function inList(values: string[]): string {
  return `in.(${values.map((v) => `"${v.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`).join(",")})`;
}

export function createDb(supabaseUrl: string, serviceKey: string): Db {
  const base = `${supabaseUrl.replace(/\/+$/, "")}/rest/v1/news_items`;
  const headers: Record<string, string> = { apikey: serviceKey, "Content-Type": "application/json" };
  // A legacy service_role key is a JWT and goes in Authorization too; a new style secret
  // key goes in apikey only.
  if (serviceKey.startsWith("eyJ")) headers.Authorization = `Bearer ${serviceKey}`;

  return {
    async knownUrls(urls) {
      const known = new Set<string>();
      for (let i = 0; i < urls.length; i += 40) {
        const chunk = urls.slice(i, i + 40);
        const q = `select=source_url&source_url=${encodeURIComponent(inList(chunk))}`;
        const rows = (await withRetries("db-select", 3, () =>
          fetchJson(`${base}?${q}`, { headers, timeoutMs: 10_000 }))) as { source_url: string }[];
        for (const r of rows) known.add(r.source_url);
      }
      return known;
    },
    async insert(row) {
      // on_conflict + ignore-duplicates: a row another run stored meanwhile is left alone.
      const rows = (await withRetries("db-insert", 3, () =>
        fetchJson(`${base}?on_conflict=source_url`, {
          method: "POST",
          headers: { ...headers, Prefer: "resolution=ignore-duplicates,return=representation" },
          body: JSON.stringify([row]),
          timeoutMs: 10_000,
        }))) as unknown[];
      return Array.isArray(rows) && rows.length > 0;
    },
  };
}
