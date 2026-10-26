// delete-account: closes the caller's Soma account. Called by the app
// (AccountDeletion.run) after the person confirmed.
//
// Closing erases nothing (owner rule, 2026-10-03, restated 2026-10-24: no
// account deletion on the server). Every row and every stored file stays,
// so an admin can reopen the account.
//
// The caller is whoever the JWT says (verify_jwt = true at the gateway, and
// the user is read back from Auth here): nobody can close another account.
// With the service role, in this order:
//   1. the profile is marked `status = 'deleted'` with `deleted_at`, through
//      PostgREST (the profiles trigger lets the service role move it);
//   2. the auth user is banned (PUT /auth/v1/admin/users/<id> with a ban
//      of a hundred years), so sign in is refused and sync stops.
// Both steps are idempotent, so a failed call can simply be retried.
// An admin reopens the account by setting the status back to active and
// lifting the ban (ban_duration "none").
//
// Environment: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (set by Supabase).
// The person's Open Health Sync user stays too, like every other row.

import { log } from "../_shared/http.ts";
import { bearer, CORS_HEADERS, json, restHeaders } from "../_shared/respond.ts";

/** A ban long enough to mean closed, short of GoTrue's limits. */
export const BAN = "876000h";

export interface Deps {
  env: (name: string) => string | undefined;
  fetch: typeof fetch;
  now?: () => Date;
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
  if (req.method !== "POST") return json(405, { error: "POST only" });
  const base = deps.env("SUPABASE_URL")?.replace(/\/+$/, "");
  const anonKey = deps.env("SUPABASE_ANON_KEY");
  const serviceKey = deps.env("SUPABASE_SERVICE_ROLE_KEY");
  if (!base || !anonKey || !serviceKey) return json(500, { error: "function not configured" });

  const token = bearer(req);
  if (!token) return json(401, { error: "sign in first" });
  const userResponse = await deps.fetch(`${base}/auth/v1/user`, { headers: { apikey: anonKey, Authorization: `Bearer ${token}` } });
  if (!userResponse.ok) return json(401, { error: "sign in first" });
  const { id } = (await userResponse.json()) as { id?: string };
  if (!id || !/^[0-9a-f-]{36}$/i.test(id)) return json(401, { error: "sign in first" });
  const userID = id.toLowerCase();

  const admin = restHeaders(serviceKey);
  if (!admin.Authorization) admin.Authorization = `Bearer ${serviceKey}`;
  const now = (deps.now ?? (() => new Date()))().toISOString();
  try {
    const marked = await deps.fetch(`${base}/rest/v1/profiles?id=eq.${userID}`, {
      method: "PATCH",
      headers: { ...admin, Prefer: "return=minimal" },
      body: JSON.stringify({ status: "deleted", deleted_at: now, updated_at: now }),
    });
    if (!marked.ok) throw new Error(`mark profile: ${marked.status}`);
    const banned = await deps.fetch(`${base}/auth/v1/admin/users/${userID}`, {
      method: "PUT",
      headers: admin,
      body: JSON.stringify({ ban_duration: BAN }),
    });
    if (!banned.ok) throw new Error(`ban user: ${banned.status}`);
    log("info", "account_closed", { user: userID });
    return json(200, { closed: true });
  } catch (err) {
    log("error", "account_close_failed", { user: userID, error: String(err) });
    return json(502, { error: "Couldn't finish closing the account. Nothing was erased; try again." });
  }
}

if (import.meta.main) {
  Deno.serve((req) => handle(req, { env: (n) => Deno.env.get(n), fetch }));
}
