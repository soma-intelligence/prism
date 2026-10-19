// Small helpers every function here uses: JSON answers, CORS for the app's
// web views, and a constant-time secret comparison.

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(status: number, body: unknown, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS, ...extra },
  });
}

// Constant-time comparison, so a bearer check doesn't leak the key byte by byte.
export function sameSecret(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

export function bearer(req: Request): string {
  return (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
}

// PostgREST headers for a key: a legacy JWT key also goes in Authorization,
// a new style secret or publishable key in apikey only.
export function restHeaders(key: string, userJwt?: string): Record<string, string> {
  const headers: Record<string, string> = { apikey: key, "Content-Type": "application/json" };
  if (userJwt) headers.Authorization = `Bearer ${userJwt}`;
  else if (key.startsWith("eyJ")) headers.Authorization = `Bearer ${key}`;
  return headers;
}
