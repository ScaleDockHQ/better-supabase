/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
/* oxlint-disable vitest/prefer-each -- Playwright has no test.each; the loop
   generates one case per route (1 finding). */
import { expect, test } from "@playwright/test";
import { expectDbBudget } from "better-supabase/testing";
import { mkdirSync, writeFileSync } from "node:fs";

import { ROUTES } from "./routes.manifest";
import { openableRoutes, perfUser, signIn } from "./support/example-session";

// Names every database call of a warm render with its wave and phase, from
// `DbStats.trace`, so a route's extra calls can be explained instead of
// counted. `BSB_EXPLAIN_ROUTES` lists the routes (comma separated manifest
// routes). Writes explain-<user>.json next to the other perf results.

const user = perfUser();

const wanted = (
  process.env["BSB_EXPLAIN_ROUTES"] ?? "/customers/[id],/crm/deals"
).split(",");

test.beforeEach(async ({ page }) => {
  await signIn(page, user);
});

for (const entry of openableRoutes(ROUTES).filter((candidate) =>
  wanted.includes(candidate.route),
)) {
  test(`${entry.route} call trace as ${user}`, async ({ page }) => {
    const heading = page.getByRole("heading", { level: 1 }).first();
    await page.goto(entry.url);
    await expect(heading).toBeVisible({ timeout: 20_000 });

    const renders = await expectDbBudget(page, {
      during: async () => {
        await page.goto(entry.url);
        await expect(heading).toBeVisible({ timeout: 20_000 });
      },
      requireRequest: false,
    });

    const dir = process.env["BSB_PERF_DIR"] ?? "perf-results/example-perf";
    mkdirSync(dir, { recursive: true });

    writeFileSync(
      `${dir}/explain-${user}-${entry.route.replaceAll(/[^a-z]+/gi, "_")}.json`,
      JSON.stringify(
        renders.map((render) => ({
          calls: render.stats.calls,
          waves: render.stats.waves,
          trace: render.stats.trace,
        })),
        null,
        2,
      ),
    );
  });
}
