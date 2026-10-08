import { describe, expect, it } from "vitest";

import type { DbStats } from "../../src/core/stats.ts";

import {
  type BudgetPage,
  type BudgetRequest,
  type BudgetResponse,
  expectDbBudget,
} from "../../src/testing/budget.ts";

function fakePage(
  renders: Record<string, DbStats>,
  during?: (
    respond: (id: string, path: string) => BudgetResponse,
    fail: (request: BudgetRequest) => void,
  ) => void,
): BudgetPage {
  let listener: ((response: BudgetResponse) => void) | undefined;
  let onFailed: ((request: BudgetRequest) => void) | undefined;
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
  const aborted = (id: string, path: string): BudgetResponse => {
    const request = { headers: () => ({}) };
    const response: BudgetResponse = {
      ...respond(id, path),
      request: () => request,
      finished: () => new Promise(() => {}),
    };
    listener?.(response);
    return response;
  };
  return {
    on: (
      event: string,
      fn: (value: BudgetResponse & BudgetRequest) => void,
    ) => {
      if (event === "response") listener = fn as typeof listener;
      else onFailed = fn as typeof onFailed;
    },
    off: (event: string) => {
      if (event === "response") listener = undefined;
      else onFailed = undefined;
    },
    reload: () => {
      if (during) {
        during(aborted, (request) => onFailed?.(request));
        return Promise.resolve();
      }
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

  it("stops waiting when the browser aborts a streamed response", async () => {
    const started = Date.now();
    const renders = await expectDbBudget(
      fakePage({ early: stats(1, 1), late: stats(2, 1) }, (respond, fail) => {
        fail(respond("early", "/customers?_rsc=1").request());
        const late = respond("late", "/customers?_rsc=2");
        setTimeout(() => {
          fail(late.request());
        }, 10);
      }),
      { maxCalls: 2, timeoutMs: 5000 },
    );
    expect(renders.map((render) => render.requestId)).toEqual([
      "early",
      "late",
    ]);
    expect(Date.now() - started).toBeLessThan(1000);
  });

  it("returns no renders when requireRequest is false and nothing was tagged", async () => {
    const empty: BudgetPage = {
      ...fakePage({}),
      reload: () => Promise.resolve(),
    };
    await expect(
      expectDbBudget(empty, { maxCalls: 0, requireRequest: false }),
    ).resolves.toEqual([]);
  });

  it("explains a missing debug route", async () => {
    await expect(
      expectDbBudget(fakePage({ doc: stats(1, 1) }), { maxCalls: 8 }),
    ).rejects.toThrow(/answered 404\. Mount bs\.debugRoute\(\)/);
  });
});

describe("expectDbBudget(response)", () => {
  const withStats = (value?: string, header = "x-bs-db-calls") =>
    new Response(null, value ? { headers: { [header]: value } } : {});

  it("returns the stats within budget", () => {
    expect(
      expectDbBudget(withStats("2;1;5"), { maxCalls: 3, maxWaves: 1 }),
    ).toEqual({
      calls: 2,
      waves: 1,
      ms: 5,
    });
    expect(
      expectDbBudget(withStats("9;9;9", "x-db"), { header: "x-db" }).calls,
    ).toBe(9);
  });

  it("fails over budget or without the header", () => {
    expect(() => expectDbBudget(withStats("4;1;5"), { maxCalls: 3 })).toThrow(
      /4 calls in 1 waves/,
    );
    expect(() => expectDbBudget(withStats("1;3;5"), { maxWaves: 2 })).toThrow(
      /over the budget/,
    );
    expect(() => expectDbBudget(withStats(), {})).toThrow(/withDbStats/);
  });
});
