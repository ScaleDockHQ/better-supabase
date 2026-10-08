import { describe, expect, it } from "vitest";

import type { DbStats } from "../../src/core/stats.ts";
import type { BudgetResponse } from "../../src/testing/budget.ts";

import {
  expectInstant,
  type InstantLocator,
  type InstantPage,
} from "../../src/testing/instant.ts";

const LOCK = "next-instant-navigation-testing";

interface Cookie {
  name: string;
  value: string;
  domain: string;
  path: string;
}

function fakePage(
  options: { url?: string; renders?: Record<string, DbStats> } = {},
) {
  let jar: Cookie[] = [];
  let listener: ((response: BudgetResponse) => void) | undefined;
  const context = {
    addCookies: (
      cookies: {
        name: string;
        value: string;
        domain?: string;
        path?: string;
        expires?: number;
      }[],
    ) => {
      for (const cookie of cookies) {
        jar = jar.filter((kept) => kept.name !== cookie.name);
        if (cookie.expires !== 1)
          jar.push({
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain ?? "",
            path: cookie.path ?? "/",
          });
      }
      return Promise.resolve();
    },
    cookies: () => Promise.resolve(jar),
  };
  const page: InstantPage = {
    url: () => options.url ?? "https://app.test/",
    context: () => context,
    on: (event: string, fn: (response: BudgetResponse) => void) => {
      if (event === "response") listener = fn;
    },
    off: (event: string) => {
      if (event === "response") listener = undefined;
    },
    reload: () => Promise.resolve(),
    request: {
      get: (url) => {
        const stats = options.renders?.[new URL(url).searchParams.get("id")!];
        return Promise.resolve({
          ok: () => stats !== undefined,
          status: () => (stats ? 200 : 404),
          json: () => Promise.resolve(stats),
        });
      },
    },
  };
  const locked = (): boolean => jar.some((cookie) => cookie.name === LOCK);
  const respond = (id: string, path: string): void =>
    listener?.({
      url: () => `https://app.test${path}`,
      request: () => ({ headers: () => ({}) }),
      headers: () => ({
        "x-bs-request-id": id,
        "x-bs-stats": `/api/bs-stats?id=${id}`,
      }),
      finished: () => Promise.resolve(null),
    });
  return { page, locked, respond, domains: () => jar.map((c) => c.domain) };
}

function locator(
  name: string,
  state: { visible?: boolean; count?: number },
  seen: string[],
  locked: () => boolean,
): InstantLocator {
  const fake = {
    toString: () => `getByText('${name}')`,
    waitFor: () => {
      seen.push(`${name} visible, locked=${String(locked())}`);
      return state.visible
        ? Promise.resolve()
        : Promise.reject(new Error("Timeout 5000ms exceeded."));
    },
    count: () => {
      seen.push(`${name} count, locked=${String(locked())}`);
      return Promise.resolve(state.count ?? 0);
    },
  };
  return fake;
}

const stats = (calls: number, waves: number): DbStats => ({
  calls,
  waves,
  tables: ["customers"],
  ms: 3,
});

describe("expectInstant", () => {
  it("checks the locators while the lock holds and releases it", async () => {
    const fake = fakePage();
    const seen: string[] = [];
    const renders = await expectInstant(fake.page, {
      during: () => {
        seen.push(`click, locked=${String(fake.locked())}`);
        return Promise.resolve();
      },
      visible: [locator("Customers", { visible: true }, seen, fake.locked)],
      absent: [locator("Unread", { count: 0 }, seen, fake.locked)],
    });
    expect(renders).toEqual([]);
    expect(seen).toEqual([
      "click, locked=true",
      "Customers visible, locked=true",
      "Unread count, locked=true",
    ]);
    expect(fake.locked()).toBe(false);
  });

  it("names a locator missing from the prefetched UI", async () => {
    const fake = fakePage();
    await expect(
      expectInstant(fake.page, {
        during: () => Promise.resolve(),
        visible: [locator("Road Runner", {}, [], fake.locked)],
      }),
    ).rejects.toThrow(
      "expectInstant: getByText('Road Runner') was not visible under the instant() lock",
    );
    expect(fake.locked()).toBe(false);
  });

  it("fails when content that should stream is already there", async () => {
    const fake = fakePage();
    await expect(
      expectInstant(fake.page, {
        during: () => Promise.resolve(),
        visible: [],
        absent: [locator("Unread", { count: 2 }, [], fake.locked)],
      }),
    ).rejects.toThrow(
      "expectInstant: getByText('Unread') matched 2 elements under the instant() lock",
    );
  });

  it("scopes the lock to baseURL on a fresh page", async () => {
    const fake = fakePage({ url: "about:blank" });
    let domains: string[] = [];
    await expectInstant(fake.page, {
      baseURL: "http://127.0.0.1:3100",
      during: () => {
        domains = fake.domains();
        return Promise.resolve();
      },
      visible: [],
    });
    expect(domains).toEqual(["127.0.0.1"]);
  });

  it("checks the database budget of the navigation", async () => {
    const fake = fakePage({ renders: { rsc: stats(9, 3) } });
    const navigate = (): Promise<void> => {
      fake.respond("rsc", "/customers?_rsc=1");
      return Promise.resolve();
    };
    await expect(
      expectInstant(fake.page, { during: navigate, visible: [], maxCalls: 9 }),
    ).resolves.toMatchObject([{ requestId: "rsc", stats: { calls: 9 } }]);
    await expect(
      expectInstant(fake.page, { during: navigate, visible: [], maxWaves: 2 }),
    ).rejects.toThrow(/over the budget of ∞ calls and 2 waves/);
  });

  it("measures the render that streams in after the lock releases", async () => {
    const fake = fakePage({ renders: { late: stats(9, 3) } });
    const navigate = (): Promise<void> => {
      setTimeout(() => {
        fake.respond("late", "/customers?_rsc=1");
      }, 20);
      return Promise.resolve();
    };
    await expect(
      expectInstant(fake.page, { during: navigate, visible: [], maxCalls: 2 }),
    ).rejects.toThrow(/over the budget of 2 calls/);
  });

  it("fails a budget when no render was measured", async () => {
    const fake = fakePage();
    await expect(
      expectInstant(fake.page, {
        during: () => Promise.resolve(),
        visible: [],
        maxCalls: 0,
        settleMs: 10,
      }),
    ).rejects.toThrow(/no response carried x-bs-request-id/);
  });
});
