// deno test --allow-read (or supabase/scripts/test-functions.sh, which runs these under Bun).
import { assert, assertEquals } from "jsr:@std/assert@1";
import { type Deps, handle } from "./index.ts";

const env: Record<string, string> = {
  SUPABASE_URL: "https://p.supabase.co",
  SUPABASE_ANON_KEY: "anon",
  SUPABASE_SERVICE_ROLE_KEY: "eyJservice",
  OHS_URL: "https://ohs.example.org/",
  OHS_API_KEY: "ohs_sk_test",
};
const user = "0f8fad5b-d9cb-469f-a165-70867728950e";
const ohsUser = "7d444840-9dc0-11d1-b245-5ffdce74fad2";

interface Call {
  method: string;
  url: string;
  body?: string;
  headers: Record<string, string>;
}

function fake(opts: { session?: boolean; linked?: boolean; createStatus?: number; env?: Record<string, string | undefined> } = {}) {
  const calls: Call[] = [];
  let linked = opts.linked ?? true;
  const f = (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const url = String(input);
    const method = init?.method ?? "GET";
    const headers = (init?.headers ?? {}) as Record<string, string>;
    calls.push({ method, url, body: init?.body ? String(init.body) : undefined, headers });
    const answer = (status: number, body?: unknown) => Promise.resolve(body === undefined ? new Response(null, { status }) : Response.json(body, { status }));
    if (url.endsWith("/auth/v1/user")) return opts.session === false ? answer(401, {}) : answer(200, { id: user });
    if (url.includes("/rest/v1/ohs_links")) {
      if (method === "POST") {
        linked = true;
        return answer(201);
      }
      return answer(200, linked ? [{ ohs_user_id: ohsUser }] : []);
    }
    if (url === "https://ohs.example.org/v1/users" && method === "POST") {
      const status = opts.createStatus ?? 201;
      return status === 201 ? answer(201, { id: ohsUser, external_ref: user, status: "active" }) : answer(status, { title: "Conflict" });
    }
    if (url.startsWith("https://ohs.example.org/v1/users?")) {
      return answer(200, { data: [{ id: "other", external_ref: "someone" }, { id: ohsUser, external_ref: user }], next_cursor: null });
    }
    const at = `https://ohs.example.org/v1/users/${ohsUser}`;
    if (url === `${at}/connections`) {
      return answer(200, { data: [{ provider: "oura", status: "active", last_sync_at: "2026-10-18T02:00:00Z", scopes: ["daily"], created_at: "x" }] });
    }
    if (url === `${at}/connect-sessions`) return answer(201, { url: "https://ohs.example.org/connect?session=abc", expires_at: "2026-10-18T03:30:00Z" });
    if (url === `${at}/connections/oura` && method === "DELETE") return answer(204);
    if (url === `${at}/connections/whoop/sync`) return answer(409, { title: "Conflict" });
    if (url.startsWith(`${at}/daily?`)) {
      const page = url.includes("cursor=") ? 2 : 1;
      return answer(200, { data: [{ date: `2026-10-0${page}`, step_count: 1000 * page }], next_cursor: page === 1 ? "c2" : null });
    }
    return answer(404, {});
  };
  const environment = { ...env, ...(opts.env ?? {}) };
  return { deps: { env: (n: string) => environment[n], fetch: f as typeof fetch } as Deps, calls };
}

const post = (body: unknown) =>
  new Request("https://p.supabase.co/functions/v1/ohs", { method: "POST", headers: { Authorization: "Bearer user-jwt" }, body: JSON.stringify(body) });

Deno.test("connections are the linked user's, with the tenant key", async () => {
  const { deps, calls } = fake();
  const response = await handle(post({ action: "connections" }), deps);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { connections: [{ provider: "oura", status: "active", last_sync_at: "2026-10-18T02:00:00Z" }] });
  const upstream = calls.filter((c) => c.url.startsWith("https://ohs.example.org/"));
  assert(upstream.every((c) => c.headers.Authorization === "Bearer ohs_sk_test"));
  assert(!calls.some((c) => c.url.startsWith("https://ohs.example.org/") && c.headers.Authorization?.includes("user-jwt")));
});

Deno.test("the first call makes the user and links it", async () => {
  const { deps, calls } = fake({ linked: false });
  assertEquals((await handle(post({ action: "connections" }), deps)).status, 200);
  const created = calls.find((c) => c.url === "https://ohs.example.org/v1/users")!;
  assertEquals(JSON.parse(created.body!), { external_ref: user });
  assertEquals(created.headers["Idempotency-Key"], `soma-account-${user}`);
  const link = calls.find((c) => c.method === "POST" && c.url.includes("/rest/v1/ohs_links"))!;
  assertEquals(JSON.parse(link.body!), { user_id: user, ohs_user_id: ohsUser });
});

Deno.test("a user already on the instance is found by its reference", async () => {
  const { deps, calls } = fake({ linked: false, createStatus: 409 });
  assertEquals((await handle(post({ action: "connections" }), deps)).status, 200);
  const link = calls.find((c) => c.method === "POST" && c.url.includes("/rest/v1/ohs_links"))!;
  assertEquals(JSON.parse(link.body!).ohs_user_id, ohsUser);
});

Deno.test("connect opens one provider's row and comes back through the return route", async () => {
  const { deps, calls } = fake();
  const response = await handle(post({ action: "connect", provider: "oura" }), deps);
  assertEquals(await response.json(), { url: "https://ohs.example.org/connect/oura?session=abc", expires_at: "2026-10-18T03:30:00Z" });
  const body = JSON.parse(calls.find((c) => c.url.endsWith("/connect-sessions"))!.body!);
  assertEquals(body.redirect_uri, "https://p.supabase.co/functions/v1/ohs/return");
  assertEquals(body.providers, ["oura"]);
});

Deno.test("the return route sends the browser back to the app with checked values only", async () => {
  const { deps } = fake();
  const back = await handle(new Request("https://p.supabase.co/functions/v1/ohs/return?status=connected&provider=oura&extra=x"), deps);
  assertEquals(back.status, 302);
  assertEquals(back.headers.get("Location"), "soma://oauth/ohs?status=connected&provider=oura");
  const odd = await handle(new Request("https://p.supabase.co/functions/v1/ohs/return?status=weird&provider=../x"), deps);
  assertEquals(odd.headers.get("Location"), "soma://oauth/ohs?status=error");
});

Deno.test("disconnect and sync", async () => {
  const { deps } = fake();
  assertEquals((await handle(post({ action: "disconnect", provider: "oura" }), deps)).status, 200);
  assertEquals((await handle(post({ action: "sync", provider: "whoop" }), deps)).status, 409);
  assertEquals((await handle(post({ action: "disconnect" }), deps)).status, 400);
});

Deno.test("daily walks the pages", async () => {
  const { deps } = fake();
  const response = await handle(post({ action: "daily", start: "2026-10-01", end: "2026-10-03" }), deps);
  assertEquals((await response.json()).data.map((d: { date: string }) => d.date), ["2026-10-01", "2026-10-02"]);
  assertEquals((await handle(post({ action: "daily", start: "yesterday", end: "2026-10-03" }), deps)).status, 400);
});

Deno.test("refusals: no session, odd provider, unknown action, no instance", async () => {
  assertEquals((await handle(post({ action: "connections" }), fake({ session: false }).deps)).status, 401);
  const { deps, calls } = fake();
  assertEquals((await handle(post({ action: "connect", provider: "../users" }), deps)).status, 400);
  assertEquals((await handle(post({ action: "drop" }), deps)).status, 400);
  assert(!calls.some((c) => c.url.includes("..")));
  const bare = fake({ env: { OHS_API_KEY: undefined } });
  assertEquals((await handle(post({ action: "connections" }), bare.deps)).status, 503);
  assertEquals(bare.calls.length, 0);
});
