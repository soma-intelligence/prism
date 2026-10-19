// deno test --allow-read (or supabase/scripts/test-functions.sh, which runs these under Bun).
import { assert, assertEquals } from "jsr:@std/assert@1";
import { type Deps, handle } from "./index.ts";

const env: Record<string, string> = { SUPABASE_URL: "https://p.supabase.co", SUPABASE_ANON_KEY: "anon", SUPABASE_SERVICE_ROLE_KEY: "eyJservice" };
const user = "0f8fad5b-d9cb-469f-a165-70867728950e";

function fake(opts: { session?: boolean; failRemove?: boolean } = {}) {
  const calls: { method: string; url: string; body?: string; auth?: string }[] = [];
  const listing: Record<string, { name: string; id: string | null }[]> = {
    [`avatars:${user}`]: [{ name: "avatar.jpg", id: "1" }],
    [`health-uploads:${user}`]: [{ name: "exports", id: null }],
    [`health-uploads:${user}/exports`]: [{ name: "2026-10-03.zip", id: "2" }],
  };
  const f = (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const url = String(input);
    const method = init?.method ?? "GET";
    const headers = (init?.headers ?? {}) as Record<string, string>;
    calls.push({ method, url, body: init?.body ? String(init.body) : undefined, auth: headers.Authorization });
    if (url.endsWith("/auth/v1/user")) return Promise.resolve(opts.session === false ? new Response("{}", { status: 401 }) : Response.json({ id: user }));
    const list = url.match(/\/storage\/v1\/object\/list\/(.+)$/);
    if (list) return Promise.resolve(Response.json(listing[`${list[1]}:${JSON.parse(String(init!.body)).prefix}`] ?? []));
    if (method === "DELETE" && url.includes("/storage/v1/object/")) return Promise.resolve(new Response("[]", { status: opts.failRemove ? 500 : 200 }));
    if (method === "DELETE" && url.includes("/auth/v1/admin/users/")) return Promise.resolve(new Response("{}", { status: 200 }));
    return Promise.resolve(new Response("", { status: 404 }));
  };
  return { deps: { env: (n: string) => env[n], fetch: f as typeof fetch } as Deps, calls };
}

const req = () => new Request("https://x/functions/v1/delete-account", { method: "POST", headers: { Authorization: "Bearer user-jwt" } });

Deno.test("removes the caller's files in both buckets, then the auth user", async () => {
  const { deps, calls } = fake();
  const response = await handle(req(), deps);
  assertEquals(response.status, 200);
  assertEquals((await response.json()).files, 2);
  const deletes = calls.filter((c) => c.method === "DELETE");
  assertEquals(deletes.map((c) => c.url), [
    "https://p.supabase.co/storage/v1/object/avatars",
    "https://p.supabase.co/storage/v1/object/health-uploads",
    `https://p.supabase.co/auth/v1/admin/users/${user}`,
  ]);
  assertEquals(JSON.parse(deletes[1].body!).prefixes, [`${user}/exports/2026-10-03.zip`]);
  assert(deletes.every((c) => c.auth === "Bearer eyJservice"));
});

Deno.test("without a session nothing is touched", async () => {
  const { deps, calls } = fake({ session: false });
  assertEquals((await handle(req(), deps)).status, 401);
  assert(!calls.some((c) => c.method === "DELETE"));
});

Deno.test("a storage failure stops before the user is deleted", async () => {
  const { deps, calls } = fake({ failRemove: true });
  assertEquals((await handle(req(), deps)).status, 502);
  assert(!calls.some((c) => c.url.includes("/admin/users/")));
});
