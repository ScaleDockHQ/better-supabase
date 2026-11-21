import { Temporal } from "temporal-polyfill";
import { describe, expect, it, vi } from "vitest";

import type { Usage, UsageStatus } from "../../src/blocks/usage/index.ts";

import { createGatewayBudget, gatewayCostOf } from "../../src/ai-sdk/index.ts";
import { AsyncResult, ok } from "../../src/core/result.ts";
import { provideTemporal } from "../../src/core/temporal.ts";

provideTemporal(Temporal);

const status = (over: Partial<UsageStatus> = {}): UsageStatus => ({
  meter: "ai.cost",
  used: 400,
  limit: 1000,
  remaining: 600,
  unlimited: false,
  period: "month",
  startsAt: undefined,
  resetsAt: Temporal.Now.instant().add({ minutes: 1 }),
  ...over,
});

const setup = (current: UsageStatus) => {
  const recordMany = vi.fn(
    () =>
      new AsyncResult(
        Promise.resolve(ok({ recorded: true, today: {}, used: {} })),
      ),
  );

  const usage = {
    current: () => new AsyncResult(Promise.resolve(ok(current))),
    recordMany,
  } as unknown as Pick<Usage, "current" | "recordMany">;

  return { budget: createGatewayBudget({ usage }), recordMany };
};

const cost = (byok = false) => ({
  ...gatewayCostOf({
    usage: { inputTokens: 10, outputTokens: 5 },
    finalStep: {
      providerMetadata: { gateway: { cost: "0.0005", generationId: "gen_9" } },
    },
  }),
  byok,
});

describe("createGatewayBudget", () => {
  it("lets a call through while budget is left", async () => {
    const { budget } = setup(status());
    const checked = await budget.check({ organizationId: "o" });

    expect(checked.data).toMatchObject({
      usedMicroUsd: 400,
      limitMicroUsd: 1000,
      remainingMicroUsd: 600,
    });
  });

  it("refuses with quota_exceeded and a retryAfter when it is used up", async () => {
    const { budget } = setup(status({ used: 1000, remaining: 0 }));
    const checked = await budget.check({ organizationId: "o" });

    expect(checked.error).toMatchObject({
      kind: "quota_exceeded",
      meter: "ai.cost",
      limit: 1000,
    });

    expect(
      checked.error?.kind === "quota_exceeded" && checked.error.retryAfter,
    ).toBeGreaterThan(0);
  });

  it("refuses when less than the estimate is left", async () => {
    const { budget } = setup(status());

    expect(
      (await budget.check({ organizationId: "o", estimateMicroUsd: 700 })).ok,
    ).toBe(false);
    expect(
      (await budget.check({ organizationId: "o", estimateMicroUsd: 600 })).ok,
    ).toBe(true);
  });

  it("has no limit without a quota", async () => {
    const { budget } = setup(
      status({ limit: undefined, remaining: undefined, unlimited: true }),
    );

    const checked = await budget.check({
      organizationId: "o",
      estimateMicroUsd: 9e9,
    });

    expect(checked.ok).toBe(true);
  });

  it("settles the cost once per generation", async () => {
    const { budget, recordMany } = setup(status());
    const settled = await budget.settle({ organizationId: "o", cost: cost() });

    expect(settled.data).toEqual({ recorded: true, pending: false });

    expect(recordMany).toHaveBeenCalledWith({
      organizationId: "o",
      entries: [{ meter: "ai.cost", quantity: 500 }],
      idempotencyKey: "ai-cost:gen_9",
      source: "ai:gateway",
    });
  });

  it("does not count a tenant's own key", async () => {
    const { budget, recordMany } = setup(status());

    const settled = await budget.settle({
      organizationId: "o",
      cost: cost(true),
    });

    expect(settled.data).toEqual({ recorded: false, pending: false });
    expect(recordMany).not.toHaveBeenCalled();
  });

  it("reports a missing cost as pending", async () => {
    const { budget, recordMany } = setup(status());

    const settled = await budget.settle({
      organizationId: "o",
      cost: { ...cost(), costMicroUsd: undefined },
    });

    expect(settled.data).toEqual({ recorded: false, pending: true });
    expect(recordMany).not.toHaveBeenCalled();
  });
});
