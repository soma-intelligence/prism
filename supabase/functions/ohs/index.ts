// ohs: the app's way to Open Health Sync, the server that signs in to the
// wearable clouds (Oura, Whoop, Withings, Garmin, Polar and the rest), pulls
// their data on a schedule and keeps it with its provenance.
//
// The instance's tenant key (OHS_API_KEY) reads every person on the instance,
// so it lives here and never in the app. The app calls with the person's own
// session; the function maps that account to one user on the instance
// (`ohs_links`, made on first use) and only ever touches that user.
//
// POST, with the person's JWT, body {"action": ...}:
//   connections                  the person's connections, one per provider
//   connect     {provider?}      a hosted connect page link for one provider, or for all
//   disconnect  {provider}       ends a connection; the data already pulled stays
//   sync        {provider}       asks the instance to pull now
//   daily       {start, end}     daily summaries, merged across sources, by date
// GET /ohs/return?status=&provider=
//   where the connect page sends the browser after consent: a redirect to
//   soma://oauth/ohs, which closes the app's web authentication session.
//
// Environment: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (set
// by Supabase); OHS_URL and OHS_API_KEY (secrets the owner sets). Without the
// two OHS values every route answers 503 and the app shows the providers as
// not available yet.

import { log } from "../_shared/http.ts";
import { bearer, CORS_HEADERS, json, restHeaders } from "../_shared/respond.ts";

export const APP_CALLBACK = "soma://oauth/ohs";
export const APP_NAME = "Soma";
const PROVIDER = /^[a-z0-9_]{1,40}$/;
const DAY = /^\d{4}-\d{2}-\d{2}$/;
// A year of days, in pages of 400; more than that is a mistake in the caller.
const MAX_DAILY_PAGES = 3;

export interface Deps {
  env: (name: string) => string | undefined;
  fetch: typeof fetch;
}

interface Config {
  base: string;
  anonKey: string;
  serviceKey: string;
  ohsURL: string;
  ohsKey: string;
}

class Upstream extends Error {
  constructor(readonly status: number, readonly where: string) {
    super(`${where}: ${status}`);
  }
}

function config(deps: Deps): Config | null {
  const base = deps.env("SUPABASE_URL")?.replace(/\/+$/, "");
  const anonKey = deps.env("SUPABASE_ANON_KEY");
  const serviceKey = deps.env("SUPABASE_SERVICE_ROLE_KEY");
  const ohsURL = deps.env("OHS_URL")?.replace(/\/+$/, "");
  const ohsKey = deps.env("OHS_API_KEY");
  if (!base || !anonKey || !serviceKey || !ohsURL || !ohsKey) return null;
  return { base, anonKey, serviceKey, ohsURL, ohsKey };
}

// The browser's way back to the app. Only the two values the app reads are
// passed on, each checked, so the redirect can't be made to carry anything else.
export function returnRedirect(url: URL): Response {
  const status = url.searchParams.get("status") === "connected" ? "connected" : "error";
  const provider = url.searchParams.get("provider") ?? "";
  const target = new URL(APP_CALLBACK);
  target.searchParams.set("status", status);
  if (PROVIDER.test(provider)) target.searchParams.set("provider", provider);
  return new Response(null, { status: 302, headers: { Location: target.toString(), "Cache-Control": "no-store" } });
}

async function callerID(req: Request, cfg: Config, deps: Deps): Promise<string | null> {
  const token = bearer(req);
  if (!token) return null;
  const response = await deps.fetch(`${cfg.base}/auth/v1/user`, { headers: { apikey: cfg.anonKey, Authorization: `Bearer ${token}` } });
  if (!response.ok) return null;
  const { id } = (await response.json()) as { id?: string };
  if (!id || !/^[0-9a-f-]{36}$/i.test(id)) return null;
  return id.toLowerCase();
}

async function ohs(cfg: Config, deps: Deps, method: string, path: string, body?: unknown, extra: Record<string, string> = {}): Promise<Response> {
  const headers: Record<string, string> = { Authorization: `Bearer ${cfg.ohsKey}`, Accept: "application/json", ...extra };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  return await deps.fetch(`${cfg.ohsURL}${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
}

async function ohsJSON<T>(cfg: Config, deps: Deps, method: string, path: string, body?: unknown): Promise<T> {
  const response = await ohs(cfg, deps, method, path, body);
  if (!response.ok) throw new Upstream(response.status, `${method} ${path.split("?")[0]}`);
  return (await response.json()) as T;
}

// The person's user on the instance: the stored link, or a new user made with
// the account id as its external reference. A user that already carries that
// reference (a link lost, or two first calls at once) is found and linked.
export async function linkedUser(cfg: Config, deps: Deps, userID: string): Promise<string> {
  const admin = restHeaders(cfg.serviceKey);
  const found = await deps.fetch(`${cfg.base}/rest/v1/ohs_links?user_id=eq.${userID}&select=ohs_user_id`, { headers: admin });
  if (!found.ok) throw new Upstream(found.status, "read ohs_links");
  const rows = (await found.json()) as { ohs_user_id: string }[];
  if (rows.length > 0) return rows[0].ohs_user_id;

  let ohsUserID: string | undefined;
  const created = await ohs(cfg, deps, "POST", "/v1/users", { external_ref: userID }, { "Idempotency-Key": `soma-account-${userID}` });
  if (created.ok) {
    ohsUserID = ((await created.json()) as { id: string }).id;
  } else if (created.status === 409) {
    let cursor: string | null = null;
    do {
      const query: string = cursor ? `?limit=1000&cursor=${encodeURIComponent(cursor)}` : "?limit=1000";
      const page: { data: { id: string; external_ref: string | null }[]; next_cursor: string | null } = await ohsJSON(cfg, deps, "GET", `/v1/users${query}`);
      ohsUserID = page.data.find((user) => user.external_ref === userID)?.id;
      cursor = ohsUserID ? null : page.next_cursor;
    } while (cursor);
  } else {
    throw new Upstream(created.status, "POST /v1/users");
  }
  if (!ohsUserID) throw new Upstream(409, "POST /v1/users");

  const saved = await deps.fetch(`${cfg.base}/rest/v1/ohs_links?on_conflict=user_id`, {
    method: "POST",
    headers: { ...admin, Prefer: "resolution=ignore-duplicates,return=minimal" },
    body: JSON.stringify({ user_id: userID, ohs_user_id: ohsUserID }),
  });
  if (!saved.ok) throw new Upstream(saved.status, "write ohs_links");
  return ohsUserID;
}

interface Connection {
  provider: string;
  status: string;
  last_sync_at?: string | null;
}

async function run(action: string, input: Record<string, unknown>, cfg: Config, deps: Deps, userID: string, returnURL: string): Promise<Response> {
  const provider = typeof input.provider === "string" ? input.provider : undefined;
  if (provider !== undefined && !PROVIDER.test(provider)) return json(400, { error: "unknown provider" });
  const user = await linkedUser(cfg, deps, userID);
  const at = `/v1/users/${user}`;

  switch (action) {
    case "connections": {
      const page = await ohsJSON<{ data: Connection[] }>(cfg, deps, "GET", `${at}/connections`);
      const connections = page.data.map(({ provider, status, last_sync_at }) => ({ provider, status, last_sync_at: last_sync_at ?? null }));
      return json(200, { connections });
    }
    case "connect": {
      const session = await ohsJSON<{ url: string; expires_at: string }>(cfg, deps, "POST", `${at}/connect-sessions`, {
        redirect_uri: returnURL,
        app_name: APP_NAME,
        ...(provider ? { providers: [provider] } : {}),
        ttl_seconds: 900,
      });
      // One provider: open its row directly rather than the whole list.
      const url = new URL(session.url);
      if (provider) url.pathname = `${url.pathname.replace(/\/+$/, "")}/${provider}`;
      return json(200, { url: url.toString(), expires_at: session.expires_at });
    }
    case "disconnect": {
      if (!provider) return json(400, { error: "provider is required" });
      const response = await ohs(cfg, deps, "DELETE", `${at}/connections/${provider}`);
      if (!response.ok && response.status !== 404) throw new Upstream(response.status, "DELETE connection");
      return json(200, { disconnected: true });
    }
    case "sync": {
      if (!provider) return json(400, { error: "provider is required" });
      const response = await ohs(cfg, deps, "POST", `${at}/connections/${provider}/sync`, {});
      if (response.status === 404 || response.status === 409) return json(409, { error: "connect again" });
      if (!response.ok) throw new Upstream(response.status, "POST sync");
      return json(202, { queued: true });
    }
    case "daily": {
      const { start, end } = input;
      if (typeof start !== "string" || typeof end !== "string" || !DAY.test(start) || !DAY.test(end)) {
        return json(400, { error: "start and end are YYYY-MM-DD" });
      }
      const data: unknown[] = [];
      let cursor: string | null = null;
      for (let page = 0; page < MAX_DAILY_PAGES; page++) {
        const query: string = `?start=${start}&end=${end}&limit=400${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`;
        const result: { data: unknown[]; next_cursor: string | null } = await ohsJSON(cfg, deps, "GET", `${at}/daily${query}`);
        data.push(...result.data);
        cursor = result.next_cursor;
        if (!cursor) break;
      }
      return json(200, { data });
    }
    default:
      return json(400, { error: "unknown action" });
  }
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
  const url = new URL(req.url);
  if (req.method === "GET" && url.pathname.endsWith("/return")) return returnRedirect(url);
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const cfg = config(deps);
  if (!cfg) return json(503, { error: "Open Health Sync is not set up" });
  const userID = await callerID(req, cfg, deps);
  if (!userID) return json(401, { error: "sign in first" });

  let input: Record<string, unknown>;
  try {
    const parsed = await req.json();
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) throw new Error("not an object");
    input = parsed as Record<string, unknown>;
  } catch {
    return json(400, { error: "body must be a JSON object" });
  }
  const action = typeof input.action === "string" ? input.action : "";

  try {
    return await run(action, input, cfg, deps, userID, `${cfg.base}/functions/v1/ohs/return`);
  } catch (err) {
    log("error", "ohs_failed", { user: userID, action, error: String(err) });
    const status = err instanceof Upstream && err.status === 429 ? 429 : 502;
    return json(status, { error: status === 429 ? "Too many requests, try again in a minute." : "Couldn't reach your connected devices. Try again." });
  }
}

if (import.meta.main) {
  Deno.serve((req) => handle(req, { env: (n) => Deno.env.get(n), fetch }));
}
