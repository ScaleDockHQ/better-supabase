import { generateText, streamText, wrapLanguageModel } from "ai";
import { convertArrayToReadableStream, MockLanguageModelV4 } from "ai/test";
import { describe, expect, it, vi } from "vitest";

import type { AiCache } from "../../../src/blocks/ai-cache/index.ts";
import type { DbError } from "../../../src/core/errors.ts";

import { cacheMiddleware } from "../../../src/ai-sdk/cache/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const USAGE = {
  inputTokens: { total: 5, noCache: 5, cacheRead: 0, cacheWrite: 0 },
  outputTokens: { total: 2, text: 2, reasoning: 0 },
};

function memoryCache(fail?: "get" | "set") {
  const entries = new Map<string, unknown>();
  const sets: { key: string; options: unknown }[] = [];
  const cache: Pick<AiCache, "get" | "set"> = {
    get: (key) =>
      fail === "get"
        ? AsyncResult.err(dbError("network", "down"))
        : AsyncResult.ok(
            entries.has(key)
              ? {
                  key,
                  organizationId: undefined,
                  kind: "generate",
                  model: undefined,
                  // SAFETY: the test reads back what it stored as JSON.
                  value: JSON.parse(JSON.stringify(entries.get(key))) as never,
                  hits: 1,
                  createdAt: Temporal.Now.instant(),
                  lastHitAt: undefined,
                  expiresAt: Temporal.Now.instant(),
                }
              : undefined,
          ),
    set: (key, value, options) => {
      if (fail === "set") return AsyncResult.err(dbError("network", "down"));
      entries.set(key, value);
      sets.push({ key, options });
      return AsyncResult.ok({
        key,
        organizationId: undefined,
        kind: "generate",
        model: undefined,
        hits: 0,
        createdAt: Temporal.Now.instant(),
        lastHitAt: undefined,
        expiresAt: Temporal.Now.instant(),
      });
    },
  };
  return { cache, entries, sets };
}

function generateModel(finish: "stop" | "error" = "stop") {
  return new MockLanguageModelV4({
    doGenerate: vi.fn(async () => ({
      content: [
        { type: "text" as const, text: "Hello" },
        {
          type: "file" as const,
          mediaType: "image/png",
          data: { type: "data" as const, data: new Uint8Array([1, 2, 3]) },
        },
      ],
      finishReason: { unified: finish, raw: finish },
      usage: USAGE,
      warnings: [],
      request: { body: "secret prompt" },
      response: {
        id: "r1",
        timestamp: new Date("2026-01-01T00:00:00Z"),
        modelId: "mock",
        headers: { "x-request-id": "1" },
        body: { raw: true },
      },
    })),
  });
}

function streamModel(parts: "ok" | "error" = "ok") {
  return new MockLanguageModelV4({
    doStream: vi.fn(async () => ({
      stream: convertArrayToReadableStream([
        { type: "stream-start" as const, warnings: [] },
        { type: "raw" as const, rawValue: { chunk: 1 } },
        { type: "text-start" as const, id: "t" },
        { type: "text-delta" as const, id: "t", delta: "Hi " },
        { type: "text-delta" as const, id: "t", delta: "there" },
        { type: "text-end" as const, id: "t" },
        ...(parts === "error"
          ? [{ type: "error" as const, error: new Error("cut off") }]
          : []),
        {
          type: "finish" as const,
          finishReason: { unified: "stop" as const, raw: "stop" },
          usage: USAGE,
        },
      ]),
    })),
  });
}

describe("cacheMiddleware", () => {
  it("answers a repeated generation from the cache", async () => {
    const { cache, sets, entries } = memoryCache();
    const inner = generateModel();
    const model = wrapLanguageModel({
      model: inner,
      middleware: cacheMiddleware({ cache, ttl: 60, organizationId: "o1" }),
    });
    const first = await generateText({ model, prompt: "Hi" });
    const second = await generateText({ model, prompt: "Hi" });
    expect(second.text).toBe(first.text);
    expect(second.files[0]?.uint8Array).toEqual(new Uint8Array([1, 2, 3]));
    expect(inner.doGenerateCalls).toHaveLength(1);
    expect(sets[0]?.options).toEqual({
      ttl: 60,
      kind: "generate",
      model: "mock-provider/mock-model-id",
      organizationId: "o1",
    });
    const stored = JSON.stringify([...entries.values()]);
    expect(stored).not.toContain("secret prompt");
    expect(stored).not.toContain("x-request-id");
    await generateText({ model, prompt: "Other" });
    expect(inner.doGenerateCalls).toHaveLength(2);
  });

  it("never caches a generation that ended in an error", async () => {
    const { cache, sets } = memoryCache();
    const model = wrapLanguageModel({
      model: generateModel("error"),
      middleware: cacheMiddleware({ cache, ttl: 60 }),
    });
    await generateText({ model, prompt: "Hi" });
    expect(sets).toEqual([]);
  });

  it("replays a cached stream without the raw parts", async () => {
    const { cache, entries } = memoryCache();
    const inner = streamModel();
    const model = wrapLanguageModel({
      model: inner,
      middleware: cacheMiddleware({ cache, ttl: 60 }),
    });
    const first = await streamText({ model, prompt: "Hi" }).text;
    const replay = streamText({ model, prompt: "Hi" });
    expect(await replay.text).toBe(first);
    expect(first).toBe("Hi there");
    expect(inner.doStreamCalls).toHaveLength(1);
    expect(JSON.stringify([...entries.values()])).not.toContain("rawValue");
  });

  it("does not cache a stream with an error part", async () => {
    const { cache, sets } = memoryCache();
    const model = wrapLanguageModel({
      model: streamModel("error"),
      middleware: cacheMiddleware({ cache, ttl: 60 }),
    });
    const result = streamText({ model, prompt: "Hi", onError: () => {} });
    await result.consumeStream();
    expect(sets).toEqual([]);
  });

  it("skips the cache when `when` says so, and keys by `key`", async () => {
    const { cache, sets } = memoryCache();
    const inner = generateModel();
    const model = wrapLanguageModel({
      model: inner,
      middleware: cacheMiddleware({
        cache,
        ttl: 60,
        when: (call) => call.params.temperature === undefined,
        key: () => "same",
      }),
    });
    await generateText({ model, prompt: "A", temperature: 1 });
    expect(sets).toEqual([]);
    await generateText({ model, prompt: "A" });
    await generateText({ model, prompt: "B" });
    expect(inner.doGenerateCalls).toHaveLength(2);
    const streaming = wrapLanguageModel({
      model: streamModel(),
      middleware: cacheMiddleware({ cache, ttl: 60, when: () => false }),
    });
    expect(await streamText({ model: streaming, prompt: "A" }).text).toBe(
      "Hi there",
    );
  });

  it("runs the call when the cache fails, and reports it", async () => {
    for (const fail of ["get", "set"] as const) {
      const errors: DbError[] = [];
      const { cache } = memoryCache(fail);
      const model = wrapLanguageModel({
        model: generateModel(),
        middleware: cacheMiddleware({
          cache,
          ttl: 60,
          onError: (error) => errors.push(error),
        }),
      });
      expect((await generateText({ model, prompt: "Hi" })).text).toBe("Hello");
      expect(errors.length).toBeGreaterThan(0);
    }
  });

  it("revives URLs and dates in a cached result", async () => {
    const { cache } = memoryCache();
    const middleware = cacheMiddleware({ cache, ttl: 60 });
    const model = new MockLanguageModelV4();
    const doGenerate = vi.fn(async () => ({
      content: [
        {
          type: "file" as const,
          mediaType: "image/png",
          data: {
            type: "url" as const,
            url: new URL("https://cdn.test/a.png"),
          },
        },
      ],
      finishReason: { unified: "stop" as const, raw: "stop" },
      usage: USAGE,
      warnings: [],
      response: { timestamp: new Date("2026-01-01T00:00:00Z") },
    }));
    const call = {
      doGenerate,
      doStream: () => Promise.reject(new Error("unused")),
      params: { prompt: [] },
      model,
    };
    await middleware.wrapGenerate!(call);
    const cached = await middleware.wrapGenerate!(call);
    expect(doGenerate).toHaveBeenCalledTimes(1);
    const file = cached.content[0];
    expect(
      file?.type === "file" && file.data.type === "url" && file.data.url,
    ).toEqual(new URL("https://cdn.test/a.png"));
    expect(cached.response?.timestamp).toEqual(
      new Date("2026-01-01T00:00:00Z"),
    );
  });
});
