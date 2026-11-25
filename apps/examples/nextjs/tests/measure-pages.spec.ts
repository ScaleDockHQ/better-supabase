/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
/* oxlint-disable vitest/prefer-each -- Playwright has no test.each; the loop
   generates one case per route of the manifest (1 finding). */
import type { Response } from "@playwright/test";

import { expect, test } from "@playwright/test";
import { expectDbBudget } from "better-supabase/testing";

import { ROUTES } from "./routes.manifest";
import {
  openableRoutes,
  perfUser,
  recordPerf,
  signIn,
} from "./support/example-session";

// Measures, without a ceiling, what one document render of every route costs:
// database calls, waves, time, token verifications, service-role calls, tables,
// cache hits and misses, and the proxy's Server-Timing phases. Each route is
// rendered twice: the first render fills the caches (`first*`), the second is
// warm. `BSB_PERF_USER=member` measures as the member. Budgets.spec.ts holds
// the ceilings; this spec only records, to pages-<user>.json.

const user = perfUser();

/** The `dur` of every Server-Timing metric of a response, by name. */
function serverTiming(response: Response | null) {
  const header = response?.headers()["server-timing"] ?? "";

  return Object.fromEntries(
    header.split(",").flatMap((part) => {
      const [name, ...params] = part.trim().split(";");
      const dur = params.find((param) => param.trim().startsWith("dur="));

      return name && dur ? [[name.trim(), Number(dur.trim().slice(4))]] : [];
    }),
  );
}

test.beforeEach(async ({ page }) => {
  await signIn(page, user);
});

for (const entry of openableRoutes(ROUTES)) {
  test(`${entry.route} render cost as ${user}`, async ({ page }) => {
    const heading = page.getByRole("heading", { level: 1 }).first();
    const measured: Record<string, number> = {};

    for (const pass of ["first", "warm"] as const) {
      let document: Response | null = null;

      const renders = await expectDbBudget(page, {
        during: async () => {
          const started = Date.now();
          document = await page.goto(entry.url);
          await expect(heading).toBeVisible({ timeout: 20_000 });
          measured[`${pass}Ms`] = Date.now() - started;
        },
        requireRequest: false,
      });

      const stats = renders.reduce(
        (worst, render) => ({
          calls: worst.calls + render.stats.calls,
          waves: Math.max(worst.waves, render.stats.waves),
          ms: Math.max(worst.ms, render.stats.ms),
          verifications: worst.verifications + render.stats.verifications,
          adminCalls: worst.adminCalls + render.stats.adminCalls,
          tables: Math.max(worst.tables, render.stats.tables.length),
          hits: worst.hits + hitsOf(render.stats.entries, false),
          misses: worst.misses + hitsOf(render.stats.entries, true),
        }),
        {
          calls: 0,
          waves: 0,
          ms: 0,
          verifications: 0,
          adminCalls: 0,
          tables: 0,
          hits: 0,
          misses: 0,
        },
      );

      const timing = serverTiming(document);

      for (const [key, value] of Object.entries(stats)) {
        measured[pass === "first" ? `first_${key}` : key] = value;
      }

      if (pass === "warm") {
        for (const [name, dur] of Object.entries(timing)) {
          measured[`timing_${name}`] = dur;
        }
      }
    }

    // A private or public entry records only its miss, so the entries the
    // first render filled and the warm render did not are the hits: visits
    // minus misses.
    measured["servedFromCache"] = Math.max(
      0,
      (measured["first_misses"] ?? 0) - (measured["misses"] ?? 0),
    );

    recordPerf(`pages-${user}.json`, entry.route, measured);
  });
}

function hitsOf(
  entries: readonly { readonly outcome: string }[] | undefined,
  misses: boolean,
): number {
  return (entries ?? []).filter((entry) =>
    misses ? entry.outcome === "miss" : entry.outcome !== "miss",
  ).length;
}
