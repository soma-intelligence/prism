// delete-account: removes the caller's Soma account and everything kept for
// it. Called by the app (AccountDeletion.run) after the person confirmed.
//
// The caller is whoever the JWT says (verify_jwt = true at the gateway, and
// the user is read back from Auth here): nobody can delete another account.
// With the service role, in this order:
//   1. every object in the caller's folder of the avatars and health-uploads
//      buckets, through the Storage API (Postgres may not delete storage rows);
//   2. the auth user (DELETE /auth/v1/admin/users/<id>), which cascades to
//      every table that references auth.users: profiles, devices, health_*,
//      the record tables, ask_conversations, ask_messages, ask_usage.
// A failure in step 1 stops before step 2, so the call can simply be retried.
//
// Environment: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (set by Supabase).

import { log } from "../_shared/http.ts";
import { bearer, CORS_HEADERS, json, restHeaders } from "../_shared/respond.ts";

export const BUCKETS = ["avatars", "health-uploads"];

export interface Deps {
  env: (name: string) => string | undefined;
  fetch: typeof fetch;
}

// Every file path under `folder`, folders walked. A folder comes back without an id.
export async function listFiles(deps: Deps, base: string, headers: Record<string, string>, bucket: string, folder: string): Promise<string[]> {
  const pending = [folder];
  const files: string[] = [];
  while (pending.length > 0) {
    const prefix = pending.pop()!;
    const response = await deps.fetch(`${base}/storage/v1/object/list/${bucket}`, {
      method: "POST",
      headers,
      body: JSON.stringify({ prefix, limit: 1000, offset: 0 }),
    });
    if (!response.ok) throw new Error(`list ${bucket}/${prefix}: ${response.status}`);
    for (const item of (await response.json()) as { name: string; id: string | null }[]) {
      if (item.id === null) pending.push(`${prefix}/${item.name}`);
      else files.push(`${prefix}/${item.name}`);
    }
  }
  return files;
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
  try {
    let removed = 0;
    for (const bucket of BUCKETS) {
      const files = await listFiles(deps, base, admin, bucket, userID);
      for (let i = 0; i < files.length; i += 100) {
        const chunk = files.slice(i, i + 100);
        const response = await deps.fetch(`${base}/storage/v1/object/${bucket}`, {
          method: "DELETE",
          headers: admin,
          body: JSON.stringify({ prefixes: chunk }),
        });
        if (!response.ok) throw new Error(`remove from ${bucket}: ${response.status}`);
        removed += chunk.length;
      }
    }
    const deleted = await deps.fetch(`${base}/auth/v1/admin/users/${userID}`, { method: "DELETE", headers: admin });
    if (!deleted.ok && deleted.status !== 404) throw new Error(`delete user: ${deleted.status}`);
    log("info", "account_deleted", { user: userID, files: removed });
    return json(200, { deleted: true, files: removed });
  } catch (err) {
    log("error", "account_delete_failed", { user: userID, error: String(err) });
    return json(502, { error: "Couldn't finish deleting. Nothing was left half done that a retry won't finish; try again." });
  }
}

if (import.meta.main) {
  Deno.serve((req) => handle(req, { env: (n) => Deno.env.get(n), fetch }));
}
