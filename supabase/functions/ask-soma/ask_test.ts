// deno test --allow-read (or supabase/scripts/test-functions.sh, which runs these under Bun).
import { assert, assertEquals } from "jsr:@std/assert@1";
import { buildMessages, cleanTitle, clientIds, parseRequest, questionTitle, readUpstream, SYSTEM_PROMPT } from "./ask.ts";
import { DEFAULT_DEPLOYMENT, type Deps, handle } from "./index.ts";

const env: Record<string, string> = {
  SUPABASE_URL: "https://qnysyehawitnlcnccyop.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_test",
  AZURE_OPENAI_ENDPOINT: "https://example-resource.openai.azure.com",
  AZURE_OPENAI_API_KEY: "azure-key",
};

function upstreamStream(chunks: string[]): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  return new ReadableStream({
    start(controller) {
      for (const c of chunks) controller.enqueue(encoder.encode(c));
      controller.close();
    },
  });
}

const modelEvents = [
  `data: {"choices":[{"delta":{"role":"assistant"}}]}\n\n`,
  `data: {"choices":[{"delta":{"content":"You slept "}}]}\n\ndata: {"choices":[{"del`,
  `ta":{"content":"7 h 10 min."}}]}\n\n`,
  `data: {"choices":[],"usage":{"prompt_tokens":312,"completion_tokens":9}}\n\n`,
  `data: [DONE]\n\n`,
];

interface Call {
  url: string;
  init?: RequestInit;
}

function fakeDeps(opts: { quota?: boolean; user?: boolean; model?: number; title?: string; titles?: string } = {}): { deps: Deps; calls: Call[] } {
  const calls: Call[] = [];
  const fakeFetch = (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const url = String(input);
    calls.push({ url, init });
    if (url.endsWith("/auth/v1/user")) {
      return Promise.resolve(opts.user === false ? new Response("{}", { status: 401 }) : Response.json({ id: "0f8fad5b-d9cb-469f-a165-70867728950e" }));
    }
    if (url.endsWith("/rpc/ask_take_quota")) return Promise.resolve(Response.json(opts.quota ?? true));
    if (url.endsWith("/openai/v1/chat/completions")) {
      if (opts.model && opts.model !== 200) return Promise.resolve(new Response("busy", { status: opts.model }));
      if (JSON.parse(String(init?.body)).stream !== true) {
        return Promise.resolve(Response.json({ choices: [{ message: { content: opts.title ?? "Last night's sleep." } }] }));
      }
      return Promise.resolve(new Response(upstreamStream(modelEvents), { headers: { "Content-Type": "text/event-stream" } }));
    }
    if (url.includes("/rest/v1/ask_messages") || url.includes("/rest/v1/ask_conversations")) return Promise.resolve(new Response(null, { status: 201 }));
    return Promise.resolve(new Response("not found", { status: 404 }));
  };
  const envFor = (n: string) => (n === "ASK_MODEL_TITLES" ? opts.titles : env[n]);
  return { deps: { env: envFor, fetch: fakeFetch as typeof fetch, now: () => new Date("2026-10-03T20:00:00Z") }, calls };
}

const request = (body: unknown, token = "user-jwt") =>
  new Request("https://x/functions/v1/ask-soma", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

const ask = {
  messages: [{ role: "user", content: "How did I sleep?" }],
  context: { sleep: { score: 82, hours: 7.2 } },
  conversation_id: "11111111-1111-4111-8111-111111111111",
  turn_id: "44444444-4444-4444-8444-444444444444",
};

Deno.test("streams the model's answer as deltas, then done, and stores both turns", async () => {
  const { deps, calls } = fakeDeps();
  const response = await handle(request(ask), deps);
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("Content-Type"), "text/event-stream");
  const text = await response.text();
  assert(text.includes(`data: {"delta":"You slept "}`));
  assert(text.includes(`data: {"delta":"7 h 10 min."}`));
  assert(text.trimEnd().endsWith(`data: {"done":true,"conversation_id":"11111111-1111-4111-8111-111111111111"}`));

  const model = calls.find((c) => c.url.endsWith("/chat/completions") && JSON.parse(String(c.init!.body)).stream === true)!;
  assertEquals(model.url, "https://example-resource.openai.azure.com/openai/v1/chat/completions");
  assertEquals((model.init!.headers as Record<string, string>)["api-key"], "azure-key");
  const sent = JSON.parse(String(model.init!.body));
  assertEquals(sent.model, DEFAULT_DEPLOYMENT);
  assertEquals(sent.model, "grok-4.6");
  assertEquals(sent.stream, true);
  assert(sent.messages[1].content.includes(`"score":82`));

  const conversation = calls.find((c) => c.url.includes("/rest/v1/ask_conversations?on_conflict=id"))!;
  assertEquals((conversation.init!.headers as Record<string, string>).Prefer, "resolution=ignore-duplicates,return=minimal");
  const opened = JSON.parse(String(conversation.init!.body));
  assertEquals(opened[0].id, "11111111-1111-4111-8111-111111111111");
  assertEquals(opened[0].title, "How did I sleep?");
  assertEquals(opened[0].kind, "ask");

  const saved = calls.find((c) => c.url.includes("/rest/v1/ask_messages"))!;
  assert(saved.url.endsWith("?on_conflict=user_id,client_id"), "messages are written once per turn");
  assertEquals((saved.init!.headers as Record<string, string>).Authorization, "Bearer user-jwt");
  assertEquals((saved.init!.headers as Record<string, string>).Prefer, "resolution=merge-duplicates,return=minimal");
  const rows = JSON.parse(String(saved.init!.body));
  assertEquals(rows.map((r: { role: string }) => r.role), ["user", "assistant"]);
  assertEquals(rows.map((r: { client_id: string }) => r.client_id), ["44444444-4444-4444-8444-444444444444:user", "44444444-4444-4444-8444-444444444444:assistant"]);
  assertEquals(rows[1].content, "You slept 7 h 10 min.");
  assertEquals(rows[1].prompt_tokens, 312);
  assertEquals(rows[1].is_error, false);
  assert(calls.indexOf(conversation) < calls.indexOf(saved), "the conversation is opened before its messages");

  const renamed = calls.find((c) => c.init?.method === "PATCH")!;
  assertEquals(renamed.url, "https://qnysyehawitnlcnccyop.supabase.co/rest/v1/ask_conversations?id=eq.11111111-1111-4111-8111-111111111111");
  assertEquals(JSON.parse(String(renamed.init!.body)), { title: "Last night's sleep" });
});

Deno.test("a follow up keeps the conversation's title, and titles can be turned off", async () => {
  const followUp = { ...ask, messages: [ask.messages[0], { role: "assistant", content: "You slept 7 h." }, { role: "user", content: "And tonight?" }] };
  const { deps, calls } = fakeDeps();
  await (await handle(request(followUp), deps)).text();
  assert(!calls.some((c) => c.init?.method === "PATCH"));
  const opened = JSON.parse(String(calls.find((c) => c.url.includes("/ask_conversations"))!.init!.body));
  assertEquals(opened[0].title, "How did I sleep?", "the first question names the conversation");

  const off = fakeDeps({ titles: "false" });
  await (await handle(request(ask), off.deps)).text();
  assert(!off.calls.some((c) => c.init?.method === "PATCH"));
});

Deno.test("titles and turn ids", () => {
  assertEquals(clientIds("t"), { user: "t:user", assistant: "t:assistant" });
  assertEquals(questionTitle("  How   did I\nsleep?  "), "How did I sleep?");
  const long = questionTitle("word ".repeat(40));
  assert(long.length <= 80 && !long.endsWith(" "));
  assertEquals(cleanTitle("\"Sleep and recovery.\"\nextra"), "Sleep and recovery");
  assertEquals(cleanTitle("Sleep \u2014 tonight"), "Sleep tonight");
  assertEquals(cleanTitle(""), null);
  assertEquals(cleanTitle(null), null);
  const parsed = parseRequest(ask);
  assert(parsed.ok);
  assertEquals(parsed.value.turnId, "44444444-4444-4444-8444-444444444444");
  const fresh = parseRequest({ messages: [{ role: "user", content: "hi" }], turn_id: "nope" });
  assert(fresh.ok && /^[0-9a-f-]{36}$/.test(fresh.value.turnId), "a bad turn id gets a fresh one");
});

Deno.test("no session is 401 and nothing is asked", async () => {
  const { deps, calls } = fakeDeps({ user: false });
  assertEquals((await handle(request(ask), deps)).status, 401);
  assert(!calls.some((c) => c.url.includes("chat/completions")));
});

Deno.test("over the hourly allowance is 429 and the model is not called", async () => {
  const { deps, calls } = fakeDeps({ quota: false });
  const response = await handle(request(ask), deps);
  assertEquals(response.status, 429);
  assert(!calls.some((c) => c.url.includes("chat/completions")));
});

Deno.test("a model failure is 502 and nothing is stored", async () => {
  const { deps, calls } = fakeDeps({ model: 503 });
  assertEquals((await handle(request(ask), deps)).status, 502);
  assert(!calls.some((c) => c.url.includes("/ask_messages")));
});

Deno.test("bad requests are refused before anything is spent", () => {
  assert(!parseRequest({ messages: [] }).ok);
  assert(!parseRequest({ messages: [{ role: "system", content: "x" }] }).ok);
  assert(!parseRequest({ messages: [{ role: "assistant", content: "x" }] }).ok, "the last turn must be the person's");
  assert(!parseRequest({ messages: [{ role: "user", content: "x" }], context: [] }).ok);
  assert(!parseRequest({ messages: [{ role: "user", content: "x" }], context: { blob: "y".repeat(20_000) } }).ok);
  const ok = parseRequest({ messages: [{ role: "user", content: " hi " }] });
  assert(ok.ok);
  assertEquals(ok.value.messages[0].content, "hi");
  assert(/^[0-9a-f-]{36}$/.test(ok.value.conversationId));
});

Deno.test("the system prompt keeps Soma's rules and the context rides as data", () => {
  for (const rule of ["Never invent a number", "Never diagnose", "see a clinician", "data is missing"]) assert(SYSTEM_PROMPT.includes(rule), rule);
  assert(!/[\u2014\u2013]/.test(SYSTEM_PROMPT));
  const parsed = parseRequest(ask);
  assert(parsed.ok);
  const messages = buildMessages(parsed.value, "2026-10-03");
  assertEquals(messages[0].content, SYSTEM_PROMPT);
  assert(messages[1].content.startsWith("Today is 2026-10-03."));
  assertEquals(messages[2], { role: "user", content: "How did I sleep?" });
});

Deno.test("upstream lines split across reads are joined", async () => {
  const events = [];
  for await (const e of readUpstream(upstreamStream(modelEvents))) events.push(e);
  assertEquals(events.filter((e) => e.delta).map((e) => e.delta).join(""), "You slept 7 h 10 min.");
  assertEquals(events.at(-1), { done: true });
});
