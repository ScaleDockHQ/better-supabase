import { Temporal } from "temporal-polyfill";
import { describe, expect, it, vi } from "vitest";

import type { AiChat } from "../../src/blocks/ai-chat/index.ts";

import {
  checkGatewayCredits,
  costUsage,
  creditsMonitor,
  GatewayCostPendingError,
  gatewayCostBackfill,
  gatewayCostEntries,
  gatewayCostOf,
  gatewayRunRelease,
} from "../../src/ai-sdk/index.ts";
import { AsyncResult, ok } from "../../src/core/result.ts";
import { provideTemporal } from "../../src/core/temporal.ts";

provideTemporal(Temporal);

const signal = new AbortController().signal;

const job = (enqueuedAt: Temporal.Instant): never =>
  ({
    id: 1,
    queue: "q",
    payload: undefined,
    attempts: 1,
    maxAttempts: 5,
    enqueuedAt,
  }) as never;

/**
 * The shape of a gateway response as the AI Gateway docs show it:
 * `providerMetadata.gateway` has `cost`, `marketCost`, `generationId` and
 * `routing`, and AI SDK 7 splits usage into input and output token details.
 */
const recorded = {
  usage: {
    inputTokens: 1200,
    outputTokens: 300,
    totalTokens: 1500,
    inputTokenDetails: {
      noCacheTokens: 200,
      cacheReadTokens: 900,
      cacheWriteTokens: 100,
    },
    outputTokenDetails: { textTokens: 180, reasoningTokens: 120 },
  },
  finalStep: {
    providerMetadata: {
      gateway: {
        cost: "0.0045405",
        marketCost: "0.005",
        generationId: "gen_01ABC",
        routing: {
          finalProvider: "anthropic",
          modelAttempts: [
            {
              providerAttempts: [
                {
                  provider: "anthropic",
                  credentialType: "system",
                  success: true,
                },
              ],
            },
          ],
        },
      },
    },
  },
};

describe("gatewayCostOf", () => {
  it("reads cost, market cost, cache and reasoning tokens", () => {
    expect(gatewayCostOf(recorded)).toEqual({
      generationId: "gen_01ABC",
      costMicroUsd: 4541,
      marketCostMicroUsd: 5000,
      inputTokens: 1200,
      outputTokens: 300,
      totalTokens: 1500,
      cacheReadTokens: 900,
      cacheWriteTokens: 100,
      reasoningTokens: 120,
      byok: false,
      provider: "anthropic",
    });
  });

  it("flags a call a tenant's own key served", () => {
    const byok = gatewayCostOf({
      ...recorded,
      finalStep: {
        providerMetadata: {
          gateway: {
            cost: "0.001",
            routing: {
              modelAttempts: [
                {
                  providerAttempts: [
                    { credentialType: "system", success: false },
                    { credentialType: "byok", success: true },
                  ],
                },
              ],
            },
          },
        },
      },
    });

    expect(byok.byok).toBe(true);
  });

  it("copes with a response without gateway metadata", () => {
    const cost = gatewayCostOf({ usage: { inputTokens: 3, outputTokens: 4 } });

    expect(cost).toMatchObject({
      costMicroUsd: undefined,
      totalTokens: 7,
      byok: undefined,
    });
  });
});

describe("costUsage and gatewayRunRelease", () => {
  it("keeps the extra token kinds on the run", () => {
    const cost = gatewayCostOf(recorded);

    expect(costUsage(cost)).toMatchObject({
      cachedInputTokens: 900,
      cacheWriteTokens: 100,
      reasoningTokens: 120,
      marketCostMicroUsd: 5000,
    });

    expect(gatewayRunRelease("completed", cost)).toMatchObject({
      status: "completed",
      generationId: "gen_01ABC",
      costMicroUsd: 4541,
    });
  });
});

describe("gatewayCostEntries", () => {
  it("records money and every token kind, and skips zeros", () => {
    const entries = gatewayCostEntries(gatewayCostOf(recorded));

    expect(entries.map((entry) => entry.meter).toSorted()).toEqual([
      "ai.cache_read_tokens",
      "ai.cache_write_tokens",
      "ai.cost",
      "ai.input_tokens",
      "ai.market_cost",
      "ai.output_tokens",
      "ai.reasoning_tokens",
    ]);
  });

  it("leaves a tenant's own key out of the money meters by default", () => {
    const cost = { ...gatewayCostOf(recorded), byok: true };

    const meters = (countByok?: boolean): string[] =>
      gatewayCostEntries(
        cost,
        {},
        countByok === undefined ? {} : { countByok },
      ).map((entry) => entry.meter);

    expect(meters()).not.toContain("ai.cost");
    expect(meters(true)).toContain("ai.cost");
    expect(meters()).toContain("ai.input_tokens");
  });
});

describe("gatewayCostBackfill", () => {
  const info = {
    totalCost: 0.0045405,
    marketCost: 0.005,
    surchargeCost: 0.0001,
    promptTokens: 1200,
    completionTokens: 300,
    cachedTokens: 900,
    cacheCreationTokens: 100,
    reasoningTokens: 120,
    isByok: false,
    providerName: "anthropic",
  };

  const setup = (getGenerationInfo: () => Promise<typeof info>) => {
    const setCost = vi.fn(() => new AsyncResult(Promise.resolve(ok(true))));

    const recordMany = vi.fn(
      () =>
        new AsyncResult(
          Promise.resolve(ok({ recorded: true, today: {}, used: {} })),
        ),
    );

    const handler = gatewayCostBackfill({
      chats: { runs: { setCost } } as unknown as Pick<AiChat, "runs">,
      gateway: { getGenerationInfo },
      usage: { recordMany },
      giveUpAfterSeconds: 3600,
    });

    return { handler, setCost, recordMany };
  };

  it("writes the run and the money meters once", async () => {
    const { handler, setCost, recordMany } = setup(async () => info);

    const result = await handler(
      { generationId: "gen_1", organizationId: "org" },
      job(Temporal.Now.instant()),
      signal,
    );

    expect(result).toMatchObject({ costMicroUsd: 4541, gaveUp: false });

    expect(setCost).toHaveBeenCalledWith({
      generationId: "gen_1",
      costMicroUsd: 4541,
      usage: expect.objectContaining({
        cacheWriteTokens: 100,
        surchargeMicroUsd: 100,
      }),
    });

    expect(recordMany).toHaveBeenCalledWith(
      expect.objectContaining({
        organizationId: "org",
        idempotencyKey: "ai-cost:gen_1",
      }),
    );
  });

  it("throws while the gateway doesn't know the generation yet", async () => {
    const { handler, setCost } = setup(async () => {
      throw Object.assign(new Error("not found"), { statusCode: 404 });
    });

    await expect(
      handler({ generationId: "gen_2" }, job(Temporal.Now.instant()), signal),
    ).rejects.toBeInstanceOf(GatewayCostPendingError);

    expect(setCost).not.toHaveBeenCalled();
  });

  it("gives up once the job is older than the limit", async () => {
    const { handler, setCost } = setup(async () => {
      throw Object.assign(new Error("not found"), { statusCode: 404 });
    });

    const old = Temporal.Now.instant().subtract({ hours: 2 });

    await expect(
      handler({ generationId: "gen_3" }, job(old), signal),
    ).resolves.toMatchObject({ gaveUp: true });

    expect(setCost).not.toHaveBeenCalled();
  });

  it("rethrows other errors", async () => {
    const { handler } = setup(async () => {
      throw Object.assign(new Error("boom"), { statusCode: 500 });
    });

    await expect(
      handler({ generationId: "gen_4" }, job(Temporal.Now.instant()), signal),
    ).rejects.toThrow("boom");
  });
});

describe("credits", () => {
  const client = (balance: string) => ({
    getCredits: async () => ({ balance, totalUsed: "12.5" }),
  });

  it("passes while a balance is left", async () => {
    const result = await checkGatewayCredits({ gateway: client("3.25") });

    expect(result).toEqual(
      ok({ balanceMicroUsd: 3_250_000, totalUsedMicroUsd: 12_500_000 }),
    );
  });

  it("fails as quota_exceeded at or below the minimum", async () => {
    const result = await checkGatewayCredits({
      gateway: client("1"),
      minimumMicroUsd: 1_000_000,
    });

    expect(result.error).toMatchObject({
      kind: "quota_exceeded",
      meter: "gateway_credits",
    });
  });

  it("calls onLow from the monitor", async () => {
    const onLow = vi.fn();

    const handler = creditsMonitor({
      gateway: client("0.5"),
      minimumMicroUsd: 1_000_000,
      onLow,
    });

    await handler(undefined, job(Temporal.Now.instant()), signal);

    expect(onLow).toHaveBeenCalledWith({
      balanceMicroUsd: 500_000,
      totalUsedMicroUsd: 12_500_000,
    });
  });
});
