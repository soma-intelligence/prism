// Chat completions on Azure AI Foundry. OpenAI-compatible v1 surface:
//   POST https://<resource>.services.ai.azure.com/openai/v1/chat/completions
//   header api-key: <key>, body { model: <deployment name>, messages, ... }
// (learn.microsoft.com/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure). An endpoint
// that already ends in /chat/completions, with or without a query string (for example the
// older .../models/chat/completions?api-version=2024-05-01-preview), is used as given.

import { fetchJson, withRetries } from "./http.ts";

export interface ChatMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

export function chatCompletionsUrl(endpoint: string): string {
  const trimmed = endpoint.trim();
  const url = new URL(trimmed);
  if (/\/chat\/completions\/?$/.test(url.pathname)) return trimmed;
  return `${trimmed.replace(/\/+$/, "")}/openai/v1/chat/completions`;
}

export function buildChatBody(
  model: string,
  messages: ChatMessage[],
  opts: { temperature?: number; maxTokens?: number } = {},
): Record<string, unknown> {
  return {
    model,
    messages,
    temperature: opts.temperature ?? 0.2,
    max_completion_tokens: opts.maxTokens ?? 400,
  };
}

export interface ChatResult {
  text: string;
  promptTokens: number;
  completionTokens: number;
}

interface ChatResponse {
  choices?: { message?: { content?: string | null }; finish_reason?: string }[];
  usage?: { prompt_tokens?: number; completion_tokens?: number };
}

export async function chat(
  cfg: { endpoint: string; apiKey: string; model: string; timeoutMs: number; attempts: number; temperature?: number; maxTokens?: number },
  messages: ChatMessage[],
): Promise<ChatResult> {
  const url = chatCompletionsUrl(cfg.endpoint);
  const data = (await withRetries("foundry", cfg.attempts, () =>
    fetchJson(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", "api-key": cfg.apiKey },
      body: JSON.stringify(buildChatBody(cfg.model, messages, { temperature: cfg.temperature, maxTokens: cfg.maxTokens })),
      timeoutMs: cfg.timeoutMs,
    }))) as ChatResponse;
  const text = data.choices?.[0]?.message?.content ?? "";
  return {
    text,
    promptTokens: data.usage?.prompt_tokens ?? 0,
    completionTokens: data.usage?.completion_tokens ?? 0,
  };
}
