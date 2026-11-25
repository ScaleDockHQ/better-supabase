/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import type { Browser, Page } from "@playwright/test";
import type { DbStats } from "better-supabase";

import { expect, test } from "@playwright/test";
import { expectDbBudget } from "better-supabase/testing";
import { spawn } from "node:child_process";
import { tmpdir } from "node:os";
import path from "node:path";

import type { Who } from "./support/example-session";

import { recordPerf, signIn } from "./support/example-session";

// Measures what a cache tier saves, in four scenarios per route:
//
// - `hard1`: the first hard load as the admin.
// - `hard2`: the second hard load as the admin (a private entry lives in the
//   browser only, so a reload starts it again).
// - `user2`: the first hard load as the member, who shares the organization.
// - `restart`: the admin's hard load on a fresh `next start` process over the
//   same remote cache and Postgres tables, which shows what a tier keeps
//   across a restart.
//
// Counts per load: database calls and waves, the entries the stats saw by kind
// and outcome, and what the remote handler was asked (`cache-handlers/
// counting.ts` through /api/bs-cache). Writes to cache-<scenario>.json.

const ROUTES = [
  "/",
  "/customers",
  "/crm/deals",
  "/finance/invoices",
  "/settings/roles",
  "/announcements",
  "/islands?scope=remote",
] as const;

const RESTART_PORT = 3102;

interface Counters {
  readonly gets: number;
  readonly hits: number;
  readonly sets: number;
  readonly bytesSet: number;
  readonly bytesRead: number;
  readonly updateTags: number;
}

/** The counts of one hard load, as the numbers `recordPerf` stores. */
function summarize(stats: readonly DbStats[], handler: Counters) {
  const entries = stats.flatMap((render) => render.entries ?? []);

  const count = (kind: string, outcome?: string): number =>
    entries.filter(
      (entry) =>
        entry.kind === kind &&
        (outcome === undefined ? true : entry.outcome === outcome),
    ).length;

  const served = (kind: string): number =>
    entries.filter((entry) => entry.kind === kind && entry.outcome !== "miss")
      .length;

  return {
    calls: stats.reduce((sum, render) => sum + render.calls, 0),
    waves: Math.max(0, ...stats.map((render) => render.waves)),
    ms: Math.max(0, ...stats.map((render) => render.ms)),
    remoteHits: served("remote"),
    remoteMisses: count("remote", "miss"),
    keptHits: served("kept"),
    keptMisses: count("kept", "miss"),
    privateMisses: count("private"),
    publicMisses: count("public"),
    keptBytes: entries.reduce((sum, entry) => sum + (entry.bytes ?? 0), 0),
    expiredTags: stats.reduce(
      (sum, render) => sum + (render.expiredTags?.length ?? 0),
      0,
    ),
    handlerGets: handler.gets,
    handlerHits: handler.hits,
    handlerSets: handler.sets,
    handlerBytesSet: handler.bytesSet,
    handlerBytesRead: handler.bytesRead,
  };
}

async function countersOf(page: Page, reset: boolean): Promise<Counters> {
  const reply = await page.request.get(
    `/api/bs-cache${reset ? "?reset=1" : ""}`,
  );

  // SAFETY: the testing route answers with the handler's counters.
  return (await reply.json()) as Counters;
}

/** One hard load of `url`, and what it cost. */
async function hardLoad(page: Page, url: string) {
  await countersOf(page, true);

  const renders = await expectDbBudget(page, {
    during: async () => {
      await page.goto(url);
      await expect(page.getByRole("heading", { level: 1 }).first()).toBeVisible(
        { timeout: 30_000 },
      );
    },
    requireRequest: false,
  });

  return summarize(
    renders.map((render) => render.stats),
    await countersOf(page, false),
  );
}

async function signedIn(
  browser: Browser,
  who: Who,
  baseURL?: string,
): Promise<Page> {
  const context = await browser.newContext(baseURL ? { baseURL } : {});
  const page = await context.newPage();

  await signIn(page, who);

  return page;
}

/**
 * Private and public entries record only a miss, so their visits are not seen.
 * A route's visits are the most misses any load of it showed (a cold hard load
 * runs every body), and a load's hits are those visits minus its misses.
 */
const visitsByRoute = new Map<string, number>();

function record(
  scenario: string,
  route: string,
  values: Record<string, number>,
): void {
  const misses = (values["privateMisses"] ?? 0) + (values["publicMisses"] ?? 0);
  const visits = Math.max(visitsByRoute.get(route) ?? 0, misses);

  visitsByRoute.set(route, visits);

  recordPerf(
    "cache.json",
    route,
    Object.fromEntries(
      Object.entries({ ...values, cacheHits: visits - misses }).map(
        ([key, value]) => [`${scenario}_${key}`, value],
      ),
    ),
  );
}

/** Starts a second `next start` on `port` with the first server's cache env. */
async function startServer(port: number): Promise<() => void> {
  const child = spawn("pnpm", ["exec", "next", "start", "-p", String(port)], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      EXPOSE_TESTING_API: "1",
      BSB_REMOTE_CACHE_DIR: path.join(tmpdir(), "bsb-example-remote-cache"),
      BSB_REMOTE_CACHE_STORE: process.env["BSB_REMOTE_CACHE_STORE"] ?? "file",
    },
    stdio: "ignore",
  });

  const deadline = Date.now() + 90_000;

  for (;;) {
    try {
      const reply = await fetch(`http://localhost:${String(port)}/login`);

      if (reply.ok) {
        break;
      }
    } catch {
      // Not listening yet.
    }

    if (Date.now() > deadline) {
      child.kill();
      throw new Error(`next start on ${String(port)} did not come up`);
    }

    await new Promise((resolve) => {
      setTimeout(resolve, 500);
    });
  }

  return () => child.kill();
}

test("hard loads, a second user and a restart", async ({ browser }) => {
  test.setTimeout(900_000);

  const admin = await signedIn(browser, "admin");

  for (const url of ROUTES) {
    record("hard1", url, await hardLoad(admin, url));
    record("hard2", url, await hardLoad(admin, url));
  }

  const member = await signedIn(browser, "member");

  for (const url of ROUTES) {
    record("user2", url, await hardLoad(member, url));
  }

  const stop = await startServer(RESTART_PORT);

  try {
    const fresh = await signedIn(
      browser,
      "admin",
      `http://localhost:${String(RESTART_PORT)}`,
    );

    for (const url of ROUTES) {
      record("restart", url, await hardLoad(fresh, url));
    }
  } finally {
    stop();
  }
});
