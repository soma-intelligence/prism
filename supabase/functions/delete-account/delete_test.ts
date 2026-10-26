// deno test --allow-read (or supabase/scripts/test-functions.sh, which runs these under Bun).
import { assert, assertEquals } from "jsr:@std/assert@1";
import { BAN, type Deps, handle } from "./index.ts";

const env: Record<string, string> = { SUPABASE_URL: "https://p.supabase.co", SUPABASE_ANON_KEY: "anon", SUPABASE_SERVICE_ROLE_KEY: "eyJservice" };
const user = "0f8fad5b-d9cb-469f-a165-70867728950e";
const now = new Date("2026-10-25T09:00:00Z");

function fake(opts: { session?: boolean; failMark?: boolean; failBan?: boolean } = {}) {
  const calls: { method: string; url: string; body?: string; auth?: string }[] = [];
  const f = (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const url = String(input);
    const method = init?.method ?? "GET";
    const headers = (init?.headers ?? {}) as Record<string, string>;
    calls.push({ method, url, body: init?.body ? String(init.body) : undefined, auth: headers.Authorization });
    if (url.endsWith("/auth/v1/user")) return Promise.resolve(opts.session === false ? new Response("{}", { status: 401 }) : Response.json({ id: user }));
    if (method === "PATCH" && url.includes("/rest/v1/profiles")) return Promise.resolve(new Response(null, { status: opts.failMark ? 500 : 204 }));
    if (method === "PUT" && url.includes("/auth/v1/admin/users/")) return Promise.resolve(new Response("{}", { status: opts.failBan ? 500 : 200 }));
    return Promise.resolve(new Response("", { status: 404 }));
  };
  return { deps: { env: (n: string) => env[n], fetch: f as typeof fetch, now: () => now } as Deps, calls };
}

const req = () => new Request("https://x/functions/v1/delete-account", { method: "POST", headers: { Authorization: "Bearer user-jwt" } });

Deno.test("marks the profile deleted and bans the user, erasing nothing", async () => {
  const { deps, calls } = fake();
  const response = await handle(req(), deps);
  assertEquals(response.status, 200);
  assertEquals((await response.json()).closed, true);
  const writes = calls.filter((c) => c.method !== "GET");
  assertEquals(writes.map((c) => `${c.method} ${c.url}`), [
    `PATCH https://p.supabase.co/rest/v1/profiles?id=eq.${user}`,
    `PUT https://p.supabase.co/auth/v1/admin/users/${user}`,
  ]);
  assertEquals(JSON.parse(writes[0].body!), { status: "deleted", deleted_at: now.toISOString(), updated_at: now.toISOString() });
  assertEquals(JSON.parse(writes[1].body!), { ban_duration: BAN });
  assert(!calls.some((c) => c.method === "DELETE"), "nothing is deleted");
  assert(writes.every((c) => c.auth === "Bearer eyJservice"));
});

Deno.test("without a session nothing is touched", async () => {
  const { deps, calls } = fake({ session: false });
  assertEquals((await handle(req(), deps)).status, 401);
  assert(!calls.some((c) => c.method !== "GET"));
});

Deno.test("a profile failure stops before the ban", async () => {
  const { deps, calls } = fake({ failMark: true });
  assertEquals((await handle(req(), deps)).status, 502);
  assert(!calls.some((c) => c.url.includes("/admin/users/")));
});

Deno.test("a ban failure reports a retry", async () => {
  const { deps } = fake({ failBan: true });
  assertEquals((await handle(req(), deps)).status, 502);
});
