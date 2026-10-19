// ask-soma: Soma's chat. The app posts the conversation and a compact JSON of
// the person's numbers; this function checks who they are, takes one message
// from their hourly allowance, asks the Azure OpenAI deployment, streams the
// answer back as server-sent events, and keeps both turns in ask_messages
// under their conversation in ask_conversations. A new conversation is titled
// from its first question, then renamed by the model in a few words.
//
// Request: POST, Authorization: Bearer <the person's Supabase JWT> (the
// gateway verifies it, verify_jwt = true), body
//   {"messages": [{"role": "user", "content": "..."}], "context": {...},
//    "conversation_id": "<uuid>", "turn_id": "<uuid>"}
// turn_id is the app's id for this question; the stored messages carry it
// (`<turn>:user`, `<turn>:assistant`), so the app's own upload of the same
// turn lands on the same rows.
// Answer: text/event-stream of
//   data: {"delta": "..."}            as the model writes
//   data: {"done": true, "conversation_id": "..."}
//   data: {"error": "..."}            if the model stops halfway
// Errors before the stream: 400 bad request, 401 no session, 429 over the
// allowance (60 messages an hour by default), 502 the model refused.
//
// Azure OpenAI v1 API: POST {AZURE_OPENAI_ENDPOINT}/openai/v1/chat/completions
// with header api-key and body {model: <deployment name>, messages, stream}.
// No api-version with v1. Source:
// https://learn.microsoft.com/azure/ai-foundry/openai/api-version-lifecycle
//
// Environment (function secrets; never in the app):
//   AZURE_OPENAI_ENDPOINT    https://<resource>.openai.azure.com
//   AZURE_OPENAI_API_KEY     the resource's key
//   AZURE_OPENAI_DEPLOYMENT  deployment name, default DEFAULT_DEPLOYMENT below
//   ASK_PER_HOUR             default 60
//   ASK_MODEL_TITLES         default true; false keeps the question as the title
//   SUPABASE_URL, SUPABASE_ANON_KEY  set by Supabase

import { log } from "../_shared/http.ts";
import { chatCompletionsUrl } from "../_shared/foundry.ts";
import { bearer, CORS_HEADERS, json, restHeaders } from "../_shared/respond.ts";
import { type AskRequest, buildMessages, chatBody, cleanTitle, clientIds, parseRequest, questionTitle, readUpstream, sse, titleBody } from "./ask.ts";

export const DEFAULT_DEPLOYMENT = "grok-4.6";

export interface Deps {
  env: (name: string) => string | undefined;
  fetch: typeof fetch;
  now: () => Date;
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const supabaseUrl = deps.env("SUPABASE_URL")?.replace(/\/+$/, "");
  const anonKey = deps.env("SUPABASE_ANON_KEY");
  const endpoint = deps.env("AZURE_OPENAI_ENDPOINT");
  const apiKey = deps.env("AZURE_OPENAI_API_KEY");
  const deployment = deps.env("AZURE_OPENAI_DEPLOYMENT") || DEFAULT_DEPLOYMENT;
  const perHour = Math.max(1, Math.min(1000, Number(deps.env("ASK_PER_HOUR")) || 60));
  if (!supabaseUrl || !anonKey || !endpoint || !apiKey) {
    log("error", "config_missing", {});
    return json(500, { error: "function not configured" });
  }

  const token = bearer(req);
  if (!token) return json(401, { error: "sign in first" });
  const userResponse = await deps.fetch(`${supabaseUrl}/auth/v1/user`, { headers: { apikey: anonKey, Authorization: `Bearer ${token}` } });
  if (!userResponse.ok) return json(401, { error: "sign in first" });
  const user = (await userResponse.json()) as { id?: string };
  if (!user.id) return json(401, { error: "sign in first" });

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "body must be JSON" });
  }
  const parsed = parseRequest(body);
  if (!parsed.ok) return json(400, { error: parsed.reason });
  const request = parsed.value;

  const rest = restHeaders(anonKey, token);
  const quota = await deps.fetch(`${supabaseUrl}/rest/v1/rpc/ask_take_quota`, { method: "POST", headers: rest, body: JSON.stringify({ per_hour: perHour }) });
  if (!quota.ok) {
    log("error", "quota_failed", { status: quota.status });
    return json(502, { error: "could not check the allowance" });
  }
  if ((await quota.json()) !== true) {
    return json(429, { error: `That's ${perHour} questions this hour. Ask again in a little while.` }, { "Retry-After": "600" });
  }

  const upstream = await deps.fetch(chatCompletionsUrl(endpoint), {
    method: "POST",
    headers: { "Content-Type": "application/json", "api-key": apiKey },
    body: JSON.stringify(chatBody(deployment, buildMessages(request, deps.now().toISOString().slice(0, 10)))),
  });
  if (!upstream.ok || !upstream.body) {
    log("error", "model_failed", { status: upstream.status, deployment });
    return json(502, { error: "Soma couldn't answer just now. Try again in a moment." });
  }

  const question = request.messages[request.messages.length - 1].content;
  const askedAt = deps.now().toISOString();
  const isFirstTurn = request.messages.length === 1;
  const modelTitles = (deps.env("ASK_MODEL_TITLES") ?? "true").toLowerCase() !== "false";
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      let answer = "";
      let failed = false;
      let promptTokens: number | null = null;
      let completionTokens: number | null = null;
      try {
        for await (const event of readUpstream(upstream.body!)) {
          if (event.delta) {
            answer += event.delta;
            controller.enqueue(sse({ delta: event.delta }));
          }
          if (event.promptTokens !== undefined) {
            promptTokens = event.promptTokens;
            completionTokens = event.completionTokens ?? null;
          }
        }
      } catch (err) {
        failed = true;
        log("error", "stream_failed", { error: String(err) });
        controller.enqueue(sse({ error: "the answer stopped halfway" }));
      }
      if (answer.length > 0) {
        await saveTurn(deps, supabaseUrl, rest, request, { question, answer, askedAt, deployment, promptTokens, completionTokens, failed });
      }
      log("info", "answered", { user: user.id, deployment, promptTokens, completionTokens, chars: answer.length });
      controller.enqueue(sse({ done: true, conversation_id: request.conversationId }));
      // The app has its answer; naming a new conversation happens after it.
      if (answer.length > 0 && !failed && isFirstTurn && modelTitles) {
        await nameConversation(deps, supabaseUrl, rest, request.conversationId, endpoint, apiKey, deployment, question, answer);
      }
      controller.close();
    },
  });
  return new Response(stream, {
    headers: { ...CORS_HEADERS, "Content-Type": "text/event-stream", "Cache-Control": "no-cache", "X-Conversation-Id": request.conversationId },
  });
}

interface Answered {
  question: string;
  answer: string;
  askedAt: string;
  deployment: string;
  promptTokens: number | null;
  completionTokens: number | null;
  failed: boolean;
}

// Stores the turn: the conversation first (kept as it is when it exists, so
// a title the model gave stays), then both messages under the app's ids for
// this turn. A turn asked again replaces the answer stored for it.
async function saveTurn(deps: Deps, supabaseUrl: string, rest: Record<string, string>, request: AskRequest, turn: Answered): Promise<void> {
  const conversation = await deps.fetch(`${supabaseUrl}/rest/v1/ask_conversations?on_conflict=id`, {
    method: "POST",
    headers: { ...rest, Prefer: "resolution=ignore-duplicates,return=minimal" },
    body: JSON.stringify([{ id: request.conversationId, kind: "ask", title: questionTitle(request.messages[0].content), created_at: turn.askedAt, updated_at: turn.askedAt }]),
  }).catch((err) => ({ ok: false, status: String(err) }) as const);
  if (!conversation.ok) log("warn", "conversation_not_saved", { status: conversation.status });

  const ids = clientIds(request.turnId);
  const rows = [
    { conversation_id: request.conversationId, client_id: ids.user, role: "user", content: turn.question.slice(0, 20000), model: null, prompt_tokens: null, completion_tokens: null, is_error: false, created_at: turn.askedAt },
    { conversation_id: request.conversationId, client_id: ids.assistant, role: "assistant", content: turn.answer.slice(0, 20000), model: turn.deployment, prompt_tokens: turn.promptTokens, completion_tokens: turn.completionTokens, is_error: turn.failed, created_at: deps.now().toISOString() },
  ];
  const saved = await deps.fetch(`${supabaseUrl}/rest/v1/ask_messages?on_conflict=user_id,client_id`, {
    method: "POST",
    headers: { ...rest, Prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify(rows),
  }).catch((err) => ({ ok: false, status: String(err) }) as const);
  if (!saved.ok) log("warn", "history_not_saved", { status: saved.status });
}

// Gives a new conversation a short title written by the model. Any failure
// leaves the question's title in place.
async function nameConversation(
  deps: Deps,
  supabaseUrl: string,
  rest: Record<string, string>,
  conversationId: string,
  endpoint: string,
  apiKey: string,
  deployment: string,
  question: string,
  answer: string,
): Promise<void> {
  try {
    const response = await deps.fetch(chatCompletionsUrl(endpoint), {
      method: "POST",
      headers: { "Content-Type": "application/json", "api-key": apiKey },
      body: JSON.stringify(titleBody(deployment, question, answer)),
    });
    if (!response.ok) return;
    const body = (await response.json()) as { choices?: { message?: { content?: string | null } }[] };
    const title = cleanTitle(body.choices?.[0]?.message?.content);
    if (!title) return;
    const patched = await deps.fetch(`${supabaseUrl}/rest/v1/ask_conversations?id=eq.${conversationId}`, {
      method: "PATCH",
      headers: { ...rest, Prefer: "return=minimal" },
      body: JSON.stringify({ title }),
    });
    if (!patched.ok) log("warn", "title_not_saved", { status: patched.status });
  } catch (err) {
    log("warn", "title_failed", { error: String(err) });
  }
}

if (import.meta.main) {
  Deno.serve((req) => handle(req, { env: (n) => Deno.env.get(n), fetch, now: () => new Date() }));
}
