import { Temporal } from "temporal-polyfill";
import { describe, expect, it, vi } from "vitest";

import type { AiChat } from "../../src/blocks/ai-chat/index.ts";

import {
  isVirtualModel,
  virtualModelCatalogRefresh,
  virtualModelInputOf,
  virtualModelSpendReconciliation,
} from "../../src/ai-sdk/index.ts";
import { AsyncResult, ok } from "../../src/core/result.ts";
import { provideTemporal } from "../../src/core/temporal.ts";

provideTemporal(Temporal);

const job = {} as never;
const signal = new AbortController().signal;

describe("virtual models", () => {
  it("recognizes the vmc/ prefix", () => {
    expect(isVirtualModel("vmc/support")).toBe(true);
    expect(isVirtualModel("vmc/")).toBe(false);
    expect(isVirtualModel("anthropic/claude")).toBe(false);
  });

  it("builds a catalog row marked virtual", () => {
    expect(
      virtualModelInputOf({
        id: "vmc/support",
        name: "Support",
        modelType: "language",
      }),
    ).toMatchObject({
      id: "vmc/support",
      provider: "virtual",
      capabilities: { virtual: true, slug: "support" },
    });
  });

  it("upserts only virtual models and never prunes", async () => {
    const upsert = vi.fn(() => new AsyncResult(Promise.resolve(ok(1))));

    const handler = virtualModelCatalogRefresh({
      chats: { models: { upsert } } as unknown as Pick<AiChat, "models">,
      gateway: {
        getAvailableModels: async () => ({
          models: [
            { id: "anthropic/claude", name: "Claude" },
            { id: "vmc/support", name: "Support" },
          ],
        }),
      },
    });

    await handler(undefined, job, signal);

    expect(upsert).toHaveBeenCalledWith({
      models: [expect.objectContaining({ id: "vmc/support" })],
      prune: false,
    });
  });
});

describe("virtualModelSpendReconciliation", () => {
  it("rolls spend by user up to organizations, once per day", async () => {
    const recordMany = vi.fn(
      () =>
        new AsyncResult(
          Promise.resolve(ok({ recorded: true, today: {}, used: {} })),
        ),
    );

    const handler = virtualModelSpendReconciliation({
      gateway: {
        getSpendReport: async () => ({
          results: [
            { user: "o1:a", totalCost: 0.5, requestCount: 2 },
            { user: "o1:b", totalCost: 0.25, requestCount: 1 },
            { user: "o2:c", totalCost: 1, requestCount: 4 },
            { user: "stranger", totalCost: 0.1 },
          ],
        }),
      },
      usage: { recordMany },
      organizationOf: (user) =>
        user.includes(":") ? user.split(":")[0] : undefined,
    });

    const result = await handler({ day: "2030-01-01" }, job, signal);

    expect(result).toEqual({
      day: "2030-01-01",
      tenants: [
        { organizationId: "o1", costMicroUsd: 750_000, requests: 3 },
        { organizationId: "o2", costMicroUsd: 1_000_000, requests: 4 },
      ],
      unattributedMicroUsd: 100_000,
    });

    expect(recordMany).toHaveBeenCalledWith(
      expect.objectContaining({
        organizationId: "o1",
        idempotencyKey: "ai-spend:2030-01-01:o1",
      }),
    );
  });
});

describe("virtualModelSpendReconciliation defaults", () => {
  it("reconciles yesterday, skips a free tenant and passes the credential type", async () => {
    const recordMany = vi.fn();
    const reports: unknown[] = [];

    const handler = virtualModelSpendReconciliation({
      gateway: {
        getSpendReport: async (params) => {
          reports.push(params);

          return {
            results: [{ user: "o1:a", totalCost: -1 }, { totalCost: 0.2 }],
          };
        },
      },
      usage: { recordMany },
      organizationOf: (user) => user.split(":")[0],
      credentialType: "byok",
      now: () => Temporal.Instant.from("2026-11-21T10:00:00Z"),
    });

    const result = await handler(undefined, job, signal);

    expect(result).toEqual({
      day: "2026-11-20",
      tenants: [{ organizationId: "o1", costMicroUsd: 0, requests: 0 }],
      unattributedMicroUsd: 200_000,
    });
    expect(reports[0]).toMatchObject({
      startDate: "2026-11-20",
      credentialType: "byok",
    });
    expect(recordMany).not.toHaveBeenCalled();
  });
});
