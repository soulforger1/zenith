import "server-only";

import { query, type Options } from "@anthropic-ai/claude-agent-sdk";
import type { ZodType } from "zod";

/** The Messages API only accepts these four image media types. */
const IMAGE_MEDIA_TYPES = ["image/jpeg", "image/png", "image/gif", "image/webp"] as const;
type ImageMediaType = (typeof IMAGE_MEDIA_TYPES)[number];

/** A subset of the Anthropic Messages API content-block shape the SDK's
 * streaming-input `SDKUserMessage` accepts — just enough for text + inline
 * base64 images, which is all the parse-task flow ever attaches. */
export type ContentBlock =
  | { type: "text"; text: string }
  | { type: "image"; source: { type: "base64"; media_type: ImageMediaType; data: string } };

/** Builds an image content block, validating the mime type against what the
 * Messages API actually accepts (pasted-in images can carry an arbitrary
 * mime type off a data URL). */
export function imageBlock(mimeType: string, data: string): ContentBlock {
  const mediaType = IMAGE_MEDIA_TYPES.find((type) => type === mimeType);
  if (!mediaType) {
    throw new ClaudeCliError(`Unsupported image type "${mimeType}" — expected one of ${IMAGE_MEDIA_TYPES.join(", ")}.`);
  }
  return { type: "image", source: { type: "base64", media_type: mediaType, data } };
}

/** These are pure text-in/JSON-or-text-out calls — no filesystem or network
 * access wanted or needed — so `tools: []` disables Claude Code's entire
 * built-in toolset. That's the actual safety boundary; `permissionMode:
 * "bypassPermissions"` just stops the subprocess from blocking on an
 * interactive prompt that (with no tools available) should never fire
 * anyway. `maxTurns` gives a little headroom over a strict 1 in case a
 * structured-output response needs an internal repair turn. */
const BASE_OPTIONS: Options = {
  tools: [],
  maxTurns: 3,
  permissionMode: "bypassPermissions",
  allowDangerouslySkipPermissions: true,
};

export class ClaudeCliError extends Error {}

function describeAssistantError(error: string): string {
  if (error === "authentication_failed") {
    return "Claude Code isn't authenticated. Run `claude login` in a terminal on this machine (requires a Claude Pro/Max subscription).";
  }
  return `Claude Code returned an error: ${error}.`;
}

async function* userMessage(blocks: ContentBlock[]) {
  yield {
    type: "user" as const,
    message: { role: "user" as const, content: blocks },
    parent_tool_use_id: null,
  };
}

/** Runs a single stateless Claude Code query and returns its final result
 * text plus any schema-constrained `structured_output` (see `runClaudeJSON`).
 * Every AI feature in this app goes through this one function. */
async function runClaudeQuery(
  prompt: string | ContentBlock[],
  options: Options,
  timeoutMs: number,
): Promise<{ result: string; structuredOutput: unknown }> {
  const abortController = new AbortController();
  const timer = setTimeout(() => abortController.abort(), timeoutMs);
  try {
    const input = Array.isArray(prompt) ? userMessage(prompt) : prompt;
    for await (const message of query({
      prompt: input,
      options: { ...BASE_OPTIONS, ...options, abortController },
    })) {
      if (message.type === "assistant" && message.error) {
        throw new ClaudeCliError(describeAssistantError(message.error));
      }
      if (message.type === "result") {
        if (message.subtype !== "success") {
          const detail = message.errors.length ? ` ${message.errors.join(" ")}` : "";
          throw new ClaudeCliError(`Claude Code didn't complete (${message.subtype}).${detail}`);
        }
        return { result: message.result, structuredOutput: message.structured_output };
      }
    }
    throw new ClaudeCliError("Claude Code exited without returning a result.");
  } catch (err) {
    if (abortController.signal.aborted) {
      throw new ClaudeCliError(`Claude Code timed out after ${timeoutMs}ms.`);
    }
    if (err instanceof ClaudeCliError) throw err;
    if (err instanceof Error && /ENOENT|command not found/i.test(err.message)) {
      throw new ClaudeCliError(
        "Claude Code CLI not found. Install it and run `claude login` (requires a Claude Pro/Max subscription).",
      );
    }
    throw err;
  } finally {
    clearTimeout(timer);
  }
}

/** Plain-prose calls (e.g. repo summarization) — no schema, just text. */
export async function runClaudeText(prompt: string, opts: { timeoutMs: number }): Promise<string> {
  const { result } = await runClaudeQuery(prompt, {}, opts.timeoutMs);
  const trimmed = result.trim();
  if (!trimmed) throw new ClaudeCliError("Claude returned an empty response.");
  return trimmed;
}

/** JSON-shaped calls. `jsonSchema` is passed to the CLI via `outputFormat`
 * (json_schema) so the model is constrained toward the right shape, same
 * spirit as Gemini's old `responseSchema` — but exactly like that Gemini
 * usage, it's not a 100% guarantee, so the result is always re-validated
 * against `zodSchema` before being trusted. Falls back to parsing `result`
 * as JSON if `structured_output` isn't present (e.g. an older CLI).
 *
 * The underlying Messages API requires a tool's `input_schema` to be
 * `type: "object"` at the root — a bare array/string schema gets rejected
 * with a 400 — so `jsonSchema` must always be an object schema. When the
 * data we actually want is an array (bulk parse, subtask list), wrap it as
 * `{ type: "object", properties: { <unwrapKey>: {...} }, required: [...] }`
 * and pass that same key as `unwrapKey` to unwrap it after the call. */
export async function runClaudeJSON<T>(
  prompt: string | ContentBlock[],
  jsonSchema: Record<string, unknown>,
  zodSchema: ZodType<T>,
  opts: { timeoutMs: number; unwrapKey?: string },
): Promise<T> {
  const { result, structuredOutput } = await runClaudeQuery(
    prompt,
    { outputFormat: { type: "json_schema", schema: jsonSchema } },
    opts.timeoutMs,
  );
  let raw: unknown = structuredOutput;
  if (raw === undefined) {
    try {
      raw = JSON.parse(stripCodeFences(result));
    } catch {
      throw new ClaudeCliError("Claude's response wasn't valid JSON.");
    }
  }
  if (opts.unwrapKey && raw && typeof raw === "object") {
    raw = (raw as Record<string, unknown>)[opts.unwrapKey];
  }
  const parsed = zodSchema.safeParse(raw);
  if (!parsed.success) throw new ClaudeCliError("Claude's response didn't match the expected format.");
  return parsed.data;
}

function stripCodeFences(text: string): string {
  const trimmed = text.trim();
  const match = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/);
  return match ? match[1].trim() : trimmed;
}
