// Network helpers: timeouts, bounded retries with backoff, size caps, and one JSON log line per
// event (Supabase shows them under Edge Functions > news-ingest > Logs).

export const USER_AGENT = "SomaNewsBot/1.0 (+https://www.somalabs.me)";

export function log(level: "info" | "warn" | "error", event: string, fields: Record<string, unknown> = {}): void {
  const line = JSON.stringify({ level, event, at: new Date().toISOString(), ...fields });
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.log(line);
}

export const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export class HttpError extends Error {
  constructor(readonly status: number, readonly url: string, readonly retryAfterMs: number | null, body: string) {
    super(`HTTP ${status} from ${new URL(url).host}: ${body.slice(0, 200)}`);
  }
}

export function isRetryable(err: unknown): boolean {
  if (err instanceof HttpError) return err.status === 408 || err.status === 429 || err.status >= 500;
  // Timeouts (AbortError, TimeoutError) and network failures (TypeError).
  return err instanceof Error && (err.name === "AbortError" || err.name === "TimeoutError" || err.name === "TypeError");
}

function retryAfterMs(res: Response): number | null {
  const h = res.headers.get("retry-after-ms") ?? res.headers.get("retry-after");
  if (!h) return null;
  const n = Number(h);
  if (Number.isFinite(n)) return res.headers.has("retry-after-ms") ? n : n * 1000;
  const date = Date.parse(h);
  return Number.isNaN(date) ? null : Math.max(0, date - Date.now());
}

export async function withRetries<T>(
  what: string,
  attempts: number,
  fn: () => Promise<T>,
): Promise<T> {
  let lastErr: unknown;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      if (attempt === attempts || !isRetryable(err)) break;
      const hinted = err instanceof HttpError ? err.retryAfterMs : null;
      const wait = Math.min(hinted ?? 1000 * 2 ** (attempt - 1) + Math.random() * 250, 20_000);
      log("warn", "retry", { what, attempt, waitMs: Math.round(wait), error: String(err) });
      await sleep(wait);
    }
  }
  throw lastErr;
}

// Reads at most maxBytes of the body, then stops: a page's <head> is all that's needed, and a
// runaway feed can't fill the function's memory.
async function readCapped(res: Response, maxBytes: number): Promise<string> {
  if (!res.body) return "";
  const reader = res.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (total < maxBytes) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    total += value.byteLength;
  }
  await reader.cancel().catch(() => {});
  const all = new Uint8Array(Math.min(total, maxBytes));
  let offset = 0;
  for (const c of chunks) {
    const part = c.subarray(0, Math.min(c.byteLength, all.byteLength - offset));
    all.set(part, offset);
    offset += part.byteLength;
    if (offset >= all.byteLength) break;
  }
  return new TextDecoder().decode(all);
}

export interface FetchedText {
  text: string;
  finalUrl: string;
}

export async function fetchText(
  url: string,
  opts: { timeoutMs: number; maxBytes: number; accept: string },
): Promise<FetchedText> {
  const res = await fetch(url, {
    redirect: "follow",
    headers: { "User-Agent": USER_AGENT, Accept: opts.accept },
    signal: AbortSignal.timeout(opts.timeoutMs),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new HttpError(res.status, url, retryAfterMs(res), body);
  }
  return { text: await readCapped(res, opts.maxBytes), finalUrl: res.url || url };
}

export async function fetchJson(
  url: string,
  init: RequestInit & { timeoutMs: number },
): Promise<unknown> {
  const { timeoutMs, ...rest } = init;
  const res = await fetch(url, { ...rest, signal: AbortSignal.timeout(timeoutMs) });
  const body = await res.text();
  if (!res.ok) throw new HttpError(res.status, url, retryAfterMs(res), body);
  return body ? JSON.parse(body) : null;
}
