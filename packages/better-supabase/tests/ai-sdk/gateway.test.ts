import { Temporal } from "temporal-polyfill";
import { describe, expect, it, vi } from "vitest";

import type { AiChat } from "../../src/blocks/ai-chat/index.ts";
import type { Usage, UsageStatus } from "../../src/blocks/usage/index.ts";

import {
  costBackfill,
  gatewayOptions,
  modelCatalogRefresh,
  modelInputOf,
  problem429,
  usageEntries,
  usageOf,
  usageQuota,
} from "../../src/ai-sdk/index.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../src/core/result.ts";
import { provideTemporal } from "../../src/core/temporal.ts";

provideTemporal(Temporal);

const job = { id: 1, queue: "q", payload: undefined, attempt: 1 } as never;
const signal = new AbortController().signal;

const status = (over: Partial<UsageStatus> = {}): UsageStatus => ({
  meter: "ai.tokens",
  used: 100,
  limit: 100,
  remaining: 0,
  unlimited: false,
  period: "month",
  startsAt: undefined,
  resetsAt: Temporal.Instant.from("2030-01-01T00:01:00Z"),
  ...over,
});

describe("gatewayOptions", () => {
  it("tags the tenant, the chat and the feature", () => {
    expect(
      gatewayOptions(
        { userId: "u", organizationId: "o", chatId: "c", feature: "chat" },
        { order: ["anthropic"], tags: ["team:x", 1] },
      ),
    ).toEqual({
      gateway: {
        order: ["anthropic"],
        user: "u",
        tags: ["org:o", "chat:c", "feature:chat", "team:x"],
      },
    });
    expect(gatewayOptions({})).toEqual({ gateway: {} });
  });
});

describe("usageOf", () => {
  it("reads the totals and the gateway cost", () => {
    expect(
      usageOf({
        totalUsage: {
          inputTokens: 10,
          outputTokens: 5,
          totalTokens: 15,
          inputTokenDetails: {
            noCacheTokens: 8,
            cacheReadTokens: 2,
            cacheWriteTokens: undefined,
          },
          outputTokenDetails: { textTokens: 4, reasoningTokens: 1 },
        },
        providerMetadata: {
          gateway: { cost: "0.0004215", generationId: "gen_1" },
        },
      }),
    ).toEqual({
      inputTokens: 10,
      outputTokens: 5,
      totalTokens: 15,
      cachedInputTokens: 2,
      reasoningTokens: 1,
      generationId: "gen_1",
      costMicroUsd: 422,
    });
  });

  it("falls back to the step usage and zero", () => {
    expect(
      usageOf({
        usage: { inputTokens: 3, outputTokens: undefined },
        providerMetadata: { gateway: { cost: 0.5 } },
      }),
    ).toMatchObject({ totalTokens: 3, costMicroUsd: 500_000 });
    expect(usageOf({ providerMetadata: { gateway: { cost: "" } } })).toEqual({
      inputTokens: 0,
      outputTokens: 0,
      totalTokens: 0,
      cachedInputTokens: 0,
      reasoningTokens: 0,
      generationId: undefined,
      costMicroUsd: undefined,
    });
    expect(
      usageOf({ providerMetadata: { gateway: { cost: -1 } } }).costMicroUsd,
    ).toBeUndefined();
  });
});

describe("usageEntries", () => {
  it("names the meters and skips zero", () => {
    const usage = usageOf({
      totalUsage: { inputTokens: 4, outputTokens: 0 },
      providerMetadata: { gateway: { cost: 0.000002 } },
    });
    expect(usageEntries(usage)).toEqual([
      { meter: "ai.input_tokens", quantity: 4 },
    ]);
    expect(
      usageEntries(usage, { input: "in", output: "out", cost: "ai.cost" }),
    ).toEqual([
      { meter: "in", quantity: 4 },
      { meter: "ai.cost", quantity: 2 },
    ]);
  });
});

describe("problem429", () => {
  it("answers a block error as is", async () => {
    const response = problem429(
      dbError("rate_limited", "slow down", { retryAfter: 7 }),
    );
    expect(response.status).toBe(429);
    expect(response.headers.get("retry-after")).toBe("7");
  });

  it("builds a quota error from a usage status", async () => {
    const response = problem429(
      status(),
      Temporal.Instant.from("2030-01-01T00:00:00Z"),
    );
    expect(response.status).toBe(429);
    expect(response.headers.get("retry-after")).toBe("60");
    expect(await response.json()).toMatchObject({
      kind: "quota_exceeded",
      meter: "ai.tokens",
      limit: 100,
    });
    const unlimited = problem429(
      status({
        limit: undefined,
        resetsAt: Temporal.Instant.from("2000-01-01T00:00:00Z"),
      }),
    );
    expect(unlimited.headers.get("retry-after")).toBe("1");
  });
});

describe("usageQuota", () => {
  const usage = (
    result: ReturnType<Usage["current"]>,
  ): Pick<Usage, "current"> => ({
    current: () => result,
  });

  it("passes while units remain or without a quota", async () => {
    expect(
      await usageQuota(
        usage(AsyncResult.from(async () => ok(status({ remaining: 5 })))),
        "m",
      )("o"),
    ).toBeUndefined();
    expect(
      await usageQuota(
        usage(
          AsyncResult.from(async () => ok(status({ remaining: undefined }))),
        ),
        "m",
      )("o"),
    ).toBeUndefined();
  });

  it("returns quota_exceeded or the read error", async () => {
    const exceeded = await usageQuota(
      usage(
        AsyncResult.from(async () =>
          ok(status({ resetsAt: Temporal.Now.instant().add({ hours: 1 }) })),
        ),
      ),
      "ai.tokens",
    )("o");
    expect(exceeded).toMatchObject({
      kind: "quota_exceeded",
      meter: "ai.tokens",
      limit: 100,
    });
    const noLimit = await usageQuota(
      usage(AsyncResult.from(async () => ok(status({ limit: undefined })))),
      "m",
    )("o");
    expect(noLimit).not.toHaveProperty("limit");
    const failed = await usageQuota(
      usage(
        AsyncResult.from<UsageStatus>(async () =>
          err(dbError("network", "down")),
        ),
      ),
      "m",
    )("o");
    expect(failed).toMatchObject({ kind: "network" });
  });
});

describe("costBackfill", () => {
  it("writes the cost and records it on the meter", async () => {
    const setCost = vi.fn(() => AsyncResult.from(async () => ok(true)));
    const record = vi.fn(() =>
      AsyncResult.from(async () => ok({ recorded: true, today: 1, used: 1 })),
    );
    const handler = costBackfill({
      chats: { runs: { setCost } } as unknown as Pick<AiChat, "runs">,
      gateway: {
        getGenerationInfo: async () => ({
          totalCost: 0.0012,
          promptTokens: 10,
          completionTokens: 4,
        }),
      },
      usage: { record },
      meter: "ai.cost",
    });
    expect(
      await handler({ generationId: "gen", organizationId: "o" }, job, signal),
    ).toBe(1200);
    expect(setCost).toHaveBeenCalledWith("gen", 1200, {
      inputTokens: 10,
      outputTokens: 4,
    });
    expect(record).toHaveBeenCalledWith("o", "ai.cost", {
      quantity: 1200,
      idempotencyKey: "ai-cost:gen",
      source: "ai:gateway",
    });
  });

  it("skips the meter without one and throws on a failed write", async () => {
    const handler = costBackfill({
      chats: {
        runs: {
          setCost: () =>
            AsyncResult.from(async () => err(dbError("not_found", "no run"))),
        },
      } as unknown as Pick<AiChat, "runs">,
      gateway: { getGenerationInfo: async () => ({ totalCost: Number.NaN }) },
    });
    await expect(handler({ generationId: "g" }, job, signal)).rejects.toThrow(
      "no run",
    );
    const quiet = costBackfill({
      chats: {
        runs: { setCost: () => AsyncResult.from(async () => ok(true)) },
      } as unknown as Pick<AiChat, "runs">,
      gateway: { getGenerationInfo: async () => ({ totalCost: 0 }) },
    });
    expect(await quiet({ generationId: "g" }, job, signal)).toBe(0);
  });
});

describe("modelCatalogRefresh", () => {
  it("upserts the language models", async () => {
    const upsert = vi.fn(() => AsyncResult.from(async () => ok(2)));
    const handler = modelCatalogRefresh({
      chats: { models: { upsert } } as unknown as Pick<AiChat, "models">,
      gateway: {
        getAvailableModels: async () => ({
          models: [
            {
              id: "openai/gpt-5",
              name: "GPT-5",
              description: "big",
              pricing: {
                input: "0.000001",
                output: "0.000002",
                cachedInputTokens: undefined,
              },
              modelType: "language",
            },
            { id: "local", name: "Local", pricing: null },
            { id: "openai/embed", name: "Embed", modelType: "embedding" },
          ],
        }),
      },
      plans: (model) => (model.id === "local" ? ["pro"] : undefined),
      prune: true,
    });
    expect(await handler(undefined, job, signal)).toBe(2);
    expect(upsert).toHaveBeenCalledWith(
      [
        {
          id: "openai/gpt-5",
          provider: "openai",
          name: "GPT-5",
          pricing: { input: "0.000001", output: "0.000002" },
          capabilities: { modelType: "language", description: "big" },
        },
        {
          id: "local",
          provider: "local",
          name: "Local",
          pricing: {},
          capabilities: {},
          plans: ["pro"],
        },
      ],
      { prune: true },
    );
  });

  it("maps one model", () => {
    expect(modelInputOf({ id: "a/b", name: "B" }, ["x"])).toMatchObject({
      provider: "a",
      plans: ["x"],
    });
  });
});
