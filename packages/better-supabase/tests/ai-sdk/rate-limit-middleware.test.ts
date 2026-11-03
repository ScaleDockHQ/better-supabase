import {
  generateText,
  streamText,
  wrapLanguageModel,
  simulateReadableStream,
} from "ai";
import { MockLanguageModelV4 } from "ai/test";
import { describe, expect, it } from "vitest";

import type {
  RateLimit,
  RateLimitDecision,
} from "../../src/rate-limit/index.ts";

import {
  aiErrorToDbError,
  rateLimitMiddleware,
} from "../../src/ai-sdk/index.ts";
import { DbException } from "../../src/core/db-exception.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";

function fakeLimit(answer: RateLimitDecision | "error") {
  const checks: unknown[] = [];

  const rateLimit: Pick<RateLimit, "check"> = {
    check: (input) => {
      checks.push(input);

      return answer === "error"
        ? AsyncResult.err(dbError("network", "down"))
        : AsyncResult.ok(answer);
    },
  };

  return { rateLimit, checks };
}

function model() {
  const calls = { generate: 0, stream: 0 };

  const inner = new MockLanguageModelV4({
    doGenerate: async () => {
      calls.generate += 1;

      return {
        content: [{ type: "text", text: "Hi" }],
        finishReason: { unified: "stop", raw: "stop" },
        usage: {
          inputTokens: { total: 1, noCache: 1, cacheRead: 0, cacheWrite: 0 },
          outputTokens: { total: 1, text: 1, reasoning: 0 },
        },
        warnings: [],
      };
    },
    doStream: async () => {
      calls.stream += 1;

      return {
        stream: simulateReadableStream({
          chunks: [
            { type: "stream-start", warnings: [] },
            {
              type: "finish",
              finishReason: { unified: "stop", raw: "stop" },
              usage: {
                inputTokens: {
                  total: 1,
                  noCache: 1,
                  cacheRead: 0,
                  cacheWrite: 0,
                },
                outputTokens: { total: 1, text: 1, reasoning: 0 },
              },
            },
          ],
        }),
      };
    },
  });

  return { inner, calls };
}

describe("rateLimitMiddleware", () => {
  it("counts the call and lets it through when allowed", async () => {
    const { rateLimit, checks } = fakeLimit({
      allowed: true,
      remaining: 4,
      retryAfter: 0,
    });

    const { inner, calls } = model();

    const wrapped = wrapLanguageModel({
      model: inner,
      middleware: rateLimitMiddleware({
        rateLimit,
        scope: "ai:chat",
        key: () => "user-1",
        organizationId: "org-1",
      }),
    });

    const result = await generateText({ model: wrapped, prompt: "Hi" });
    expect(result.text).toBe("Hi");
    expect(calls.generate).toBe(1);
    expect(checks).toEqual([
      { scope: "ai:chat", key: "user-1", organizationId: "org-1" },
    ]);
  });

  it("refuses before the model runs with a rate_limited error", async () => {
    const { rateLimit } = fakeLimit({
      allowed: false,
      remaining: 0,
      retryAfter: 12.2,
    });

    const { inner, calls } = model();

    const wrapped = wrapLanguageModel({
      model: inner,
      middleware: rateLimitMiddleware({ rateLimit, scope: "ai", key: "k" }),
    });

    const failure = await generateText({ model: wrapped, prompt: "Hi" }).then(
      () => undefined,
      (error: unknown) => error,
    );

    expect(failure).toBeInstanceOf(DbException);
    expect(aiErrorToDbError(failure)).toMatchObject({
      kind: "rate_limited",
      code: "AI_RATE_LIMITED",
      retryAfter: 13,
    });

    const streamErrors: unknown[] = [];

    await streamText({
      model: wrapped,
      prompt: "Hi",
      onError: ({ error }) => streamErrors.push(error),
    }).consumeStream();
    expect(streamErrors[0]).toBeInstanceOf(DbException);
    expect(calls).toEqual({ generate: 0, stream: 0 });
  });

  it("skips calls without a key and honors failOpen", async () => {
    const { rateLimit, checks } = fakeLimit("error");
    const { inner, calls } = model();

    const unkeyed = wrapLanguageModel({
      model: inner,
      middleware: rateLimitMiddleware({
        rateLimit,
        scope: "ai",
        key: () => undefined,
      }),
    });

    await generateText({ model: unkeyed, prompt: "Hi" });
    expect(checks).toEqual([]);

    const closed = wrapLanguageModel({
      model: inner,
      middleware: rateLimitMiddleware({ rateLimit, scope: "ai", key: "k" }),
    });

    await expect(
      generateText({ model: closed, prompt: "Hi" }),
    ).rejects.toMatchObject({ kind: "network" });

    const open = wrapLanguageModel({
      model: inner,
      middleware: rateLimitMiddleware({
        rateLimit,
        scope: "ai",
        key: "k",
        failOpen: true,
      }),
    });

    await generateText({ model: open, prompt: "Hi" });
    expect(calls.generate).toBe(2);
  });
});
