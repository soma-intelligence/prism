// Ask Soma's rules: the system prompt, the checks on what the app sends, and
// the reading of Azure OpenAI's streamed answer. Pure, tested by ask_test.ts.

export interface Turn {
  role: "user" | "assistant";
  content: string;
}

export interface AskRequest {
  messages: Turn[];
  context: Record<string, unknown>;
  conversationId: string;
  // The app's id for this question and its answer. Both rows are stored
  // under it (`<turn>:user`, `<turn>:assistant`), the ids the app uploads
  // the same turn with, so a turn is one pair of rows whoever writes it.
  turnId: string;
}

export const MAX_TURNS = 30;
export const MAX_TURN_CHARS = 4000;
export const MAX_CONTEXT_BYTES = 16_000;

export const SYSTEM_PROMPT = `You are Soma, the assistant inside a wellness app.
Answer in plain, short, practical sentences. Wellness only.
Use only the numbers in the person's context. Never invent a number, a trend or a reading that is not there.
When the context has nothing for what they ask, say the data is missing and what would fill it (wearing the watch at night, logging, a lab report).
Never diagnose, never name a condition they might have, never suggest a drug, a dose or a treatment.
For anything that sounds concerning (chest pain, fainting, very high or low readings, thoughts of self harm), say plainly to see a clinician or call emergency services, and keep it short.
Do not use dashes as punctuation. No exclamation marks.`;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type Parsed = { ok: true; value: AskRequest } | { ok: false; reason: string };

export function parseRequest(body: unknown): Parsed {
  if (typeof body !== "object" || body === null) return { ok: false, reason: "body must be a JSON object" };
  const b = body as Record<string, unknown>;
  if (!Array.isArray(b.messages) || b.messages.length === 0) return { ok: false, reason: "messages must be a non empty array" };
  if (b.messages.length > MAX_TURNS) return { ok: false, reason: `at most ${MAX_TURNS} messages` };
  const messages: Turn[] = [];
  for (const m of b.messages) {
    const turn = m as Record<string, unknown>;
    if ((turn.role !== "user" && turn.role !== "assistant") || typeof turn.content !== "string") {
      return { ok: false, reason: "each message needs role user or assistant and a content string" };
    }
    const content = turn.content.trim();
    if (content.length === 0 || content.length > MAX_TURN_CHARS) return { ok: false, reason: `a message must be 1 to ${MAX_TURN_CHARS} characters` };
    messages.push({ role: turn.role, content });
  }
  if (messages[messages.length - 1].role !== "user") return { ok: false, reason: "the last message must be the person's" };
  const context = b.context ?? {};
  if (typeof context !== "object" || Array.isArray(context)) return { ok: false, reason: "context must be a JSON object" };
  if (new TextEncoder().encode(JSON.stringify(context)).length > MAX_CONTEXT_BYTES) return { ok: false, reason: "context is too large" };
  const conversationId = typeof b.conversation_id === "string" && UUID.test(b.conversation_id) ? b.conversation_id.toLowerCase() : crypto.randomUUID();
  const turnId = typeof b.turn_id === "string" && UUID.test(b.turn_id) ? b.turn_id.toLowerCase() : crypto.randomUUID();
  return { ok: true, value: { messages, context: context as Record<string, unknown>, conversationId, turnId } };
}

// The message ids of one turn, the same ones the app uses.
export function clientIds(turnId: string): { user: string; assistant: string } {
  return { user: `${turnId}:user`, assistant: `${turnId}:assistant` };
}

// A conversation's first title: its first question on one line, at most 80
// characters, cut at a word when there is one to cut at. The database's
// ask_title() does the same for turns the app uploads.
export function questionTitle(question: string): string {
  const line = question.replace(/\s+/g, " ").trim();
  if (line.length <= 80) return line;
  const cut = line.slice(0, 80);
  const space = cut.lastIndexOf(" ");
  return (space > 40 ? cut.slice(0, space) : cut).trim();
}

export const TITLE_PROMPT = `Name this conversation in 2 to 6 plain words, like a note's title.
No quotes, no full stop, no dashes, no emoji. Reply with the title only.`;

// The model call that names a new conversation from its first turn.
export function titleBody(deployment: string, question: string, answer: string): Record<string, unknown> {
  return {
    model: deployment,
    messages: [
      { role: "system", content: TITLE_PROMPT },
      { role: "user", content: `Question: ${question.slice(0, 1000)}\nAnswer: ${answer.slice(0, 1000)}` },
    ],
    max_completion_tokens: 24,
  };
}

// The model's title cleaned to one short line, or null when nothing usable
// came back (the question's title then stays).
export function cleanTitle(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const line = raw.split("\n")[0].replace(/[\u2014\u2013]/g, " ").replace(/^["'\s]+|["'.\s]+$/g, "").replace(/\s+/g, " ").trim();
  if (line.length < 2 || line.length > 80) return null;
  return line;
}

export function buildMessages(request: AskRequest, today: string): { role: string; content: string }[] {
  return [
    { role: "system", content: SYSTEM_PROMPT },
    { role: "system", content: `Today is ${today}. The person's numbers, as the app shows them (JSON):\n${JSON.stringify(request.context)}` },
    ...request.messages,
  ];
}

export function chatBody(deployment: string, messages: { role: string; content: string }[]): Record<string, unknown> {
  return {
    model: deployment,
    messages,
    stream: true,
    stream_options: { include_usage: true },
    max_completion_tokens: 700,
  };
}

export interface StreamEvent {
  delta?: string;
  promptTokens?: number;
  completionTokens?: number;
  done?: boolean;
}

// Reads Azure OpenAI's server-sent events ("data: {...}" lines, ending with
// "data: [DONE]") and yields the text deltas and the usage.
export async function* readUpstream(body: ReadableStream<Uint8Array>): AsyncGenerator<StreamEvent> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    let newline: number;
    while ((newline = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, newline).trim();
      buffer = buffer.slice(newline + 1);
      if (!line.startsWith("data:")) continue;
      const data = line.slice(5).trim();
      if (data === "[DONE]") {
        yield { done: true };
        return;
      }
      try {
        const chunk = JSON.parse(data) as {
          choices?: { delta?: { content?: string | null } }[];
          usage?: { prompt_tokens?: number; completion_tokens?: number } | null;
        };
        const delta = chunk.choices?.[0]?.delta?.content;
        if (delta) yield { delta };
        if (chunk.usage) yield { promptTokens: chunk.usage.prompt_tokens ?? 0, completionTokens: chunk.usage.completion_tokens ?? 0 };
      } catch {
        // A keep-alive or a partial line the next read completes.
      }
    }
  }
  yield { done: true };
}

// One server-sent event to the app.
export function sse(payload: Record<string, unknown>): Uint8Array {
  return new TextEncoder().encode(`data: ${JSON.stringify(payload)}\n\n`);
}
