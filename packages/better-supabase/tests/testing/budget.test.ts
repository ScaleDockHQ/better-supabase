import { describe, expect, it } from "vitest";

import type { DbStats } from "../../src/core/stats.ts";

import {
  type BudgetPage,
  type BudgetResponse,
  expectDbBudget,
} from "../../src/testing/budget.ts";

function fakePage(renders: Record<string, DbStats>): BudgetPage {
  let listener: ((response: BudgetResponse) => void) | undefined;
  const respond = (
    id: string,
    path: string,
    request: Record<string, string> = {},
  ): BudgetResponse => ({
    url: () => `https://app.test${path}`,
    request: () => ({ headers: () => request }),
    headers: () => ({
      "x-bs-request-id": id,
      "x-bs-stats": `/api/bs-stats?id=${id}`,
    }),
    finished: () => Promise.resolve(null),
  });
  return {
    on: (_event, fn) => {
      listener = fn;
    },
    off: () => {
      listener = undefined;
    },
    reload: () => {
      listener?.(respond("doc", "/customers"));
      listener?.(respond("rsc", "/customers?_rsc=1"));
      listener?.(
        respond("prefetch", "/inbox?_rsc=2", { "next-router-prefetch": "1" }),
      );
      listener?.({
        url: () => "https://app.test/logo.png",
        request: () => ({ headers: () => ({}) }),
        headers: () => ({}),
        finished: () => Promise.resolve(null),
      });
      return Promise.resolve();
    },
    request: {
      get: (url) => {
        const id = new URL(url).searchParams.get("id")!;
        const stats = renders[id];
        return Promise.resolve({
          ok: () => stats !== undefined,
          status: () => (stats ? 200 : 404),
          json: () => Promise.resolve(stats),
        });
      },
    },
  };
}

const stats = (calls: number, waves: number): DbStats => ({
  calls,
  waves,
  tables: ["customers"],
  ms: 3,
});

describe("expectDbBudget", () => {
  it("measures every render during the navigation", async () => {
    const renders = await expectDbBudget(
      fakePage({ doc: stats(3, 1), rsc: stats(1, 1) }),
      { maxCalls: 3, maxWaves: 1 },
    );
    expect(
      renders.map((render) => [render.requestId, render.stats.calls]),
    ).toEqual([
      ["doc", 3],
      ["rsc", 1],
    ]);
  });

  it("fails with the renders over budget", async () => {
    await expect(
      expectDbBudget(fakePage({ doc: stats(9, 4), rsc: stats(1, 1) }), {
        maxCalls: 8,
        maxWaves: 2,
      }),
    ).rejects.toThrow(
      /over the budget of 8 calls and 2 waves:\n {2}https:\/\/app\.test\/customers: 9 calls in 4 waves \(customers\)/,
    );
  });

  it("explains a missing debug route", async () => {
    await expect(
      expectDbBudget(fakePage({ doc: stats(1, 1) }), { maxCalls: 8 }),
    ).rejects.toThrow(/answered 404\. Mount next\.debugRoute\(\)/);
  });
});
