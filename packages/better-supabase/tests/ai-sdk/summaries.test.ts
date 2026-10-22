import { MockLanguageModelV4 } from "ai/test";
import { describe, expect, it, vi } from "vitest";

import type { ThreadSummaryInput } from "../../src/ai-sdk/index.ts";
import type { AiKeys } from "../../src/blocks/ai-keys/index.ts";

import { summarizeWith } from "../../src/ai-sdk/index.ts";
import { AsyncResult } from "../../src/core/result.ts";

type CallOptions = Parameters<MockLanguageModelV4["doGenerate"]>[0];

function textModel(text: string) {
  const calls: CallOptions[] = [];

  const model = new MockLanguageModelV4({
    doGenerate: async (options) => {
      calls.push(options);

      return {
        content: [{ type: "text", text }],
        finishReason: { unified: "stop", raw: "stop" },
        usage: {
          inputTokens: { total: 5, noCache: 5, cacheRead: 0, cacheWrite: 0 },
          outputTokens: { total: 5, text: 5, reasoning: 0 },
        },
        warnings: [],
      };
    },
  });

  return { calls, model };
}

const input: ThreadSummaryInput = {
  organizationId: "org",
  conversationId: "c1",
  threadId: undefined,
  previous: undefined,
  messages: [
    {
      id: "m1",
      authorId: "u1",
      authorName: "Ada",
      body: "Ship Friday?",
      sentAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
    },
    {
      id: "m2",
      authorId: "u2",
      authorName: undefined,
      body: "Yes.",
      sentAt: Temporal.Instant.from("2026-01-01T00:01:00Z"),
    },
    {
      id: "m3",
      authorId: undefined,
      authorName: undefined,
      body: "Agreed.",
      sentAt: Temporal.Instant.from("2026-01-01T00:02:00Z"),
    },
  ],
};

const promptText = (call: CallOptions | undefined): string =>
  JSON.stringify(call?.prompt);

describe("summarizeWith", () => {
  it("summarizes with the default prompt and tags the spend", async () => {
    const { calls, model } = textModel("  Ada ships Friday.  ");
    const summarizer = summarizeWith(model, { maxOutputTokens: 300 });

    expect(summarizer.apiVersion).toBe(1);
    expect(await summarizer.summarize(input)).toEqual({
      summary: "Ada ships Friday.",
      model: "mock-provider/mock-model-id",
    });

    const prompt = promptText(calls[0]);
    expect(prompt).toContain("Summarize this team conversation");
    expect(prompt).toContain("[2026-01-01T00:00:00Z] Ada: Ship Friday?");
    expect(prompt).toContain("u2: Yes.");
    expect(prompt).toContain("Someone: Agreed.");
    expect(prompt).not.toContain("Previous summary");
    expect(calls[0]?.maxOutputTokens).toBe(300);
    expect(calls[0]?.providerOptions?.["gateway"]).toMatchObject({
      tags: ["org:org", "feature:summary"],
    });
  });

  it("updates a previous summary with the tenant's own keys", async () => {
    const { calls, model } = textModel("Updated.");

    const resolve = vi.fn(() =>
      AsyncResult.ok([
        { id: "k1", provider: "anthropic", token: "sk-tenant", settings: {} },
      ]),
    );

    // SAFETY: summarizeWith reads keys.resolve only.
    const providers = { keys: { resolve } } as unknown as Pick<AiKeys, "keys">;

    const signal = new AbortController().signal;

    await summarizeWith(model, {
      providers,
      instructions: "Be brief.",
      gateway: { order: ["anthropic"] },
    }).summarize({ ...input, previous: "Ada asked.", signal });

    expect(resolve).toHaveBeenCalledWith("org", { signal });
    expect(promptText(calls[0])).toContain("Be brief.");
    expect(promptText(calls[0])).toContain("Previous summary:\\nAda asked.");
    expect(calls[0]?.providerOptions?.["gateway"]).toMatchObject({
      order: ["anthropic"],
      byok: { anthropic: [{ apiKey: "sk-tenant" }] },
    });
  });
});
