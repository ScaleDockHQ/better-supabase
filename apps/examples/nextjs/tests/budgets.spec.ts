/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
/* oxlint-disable vitest/prefer-each -- Playwright has no test.each; the loop
   generates one case per route of the manifest (1 finding). */
import { expect, test } from "@playwright/test";
import { expectDbBudget } from "better-supabase/testing";

import { ROUTES } from "./routes.manifest";
import { openableRoutes, recordPerf, signIn } from "./support/example-session";

// One database budget per route, from the route manifest: a document render
// makes at most `maxCalls` calls in `maxWaves` waves. The measured numbers go
// to test-results/example-perf/budgets.json for `pnpm example:perf-report`.
// Needs the production build with the testing API and the debug route.

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

for (const entry of openableRoutes(ROUTES)) {
  test(`${entry.route} stays inside its database budget`, async ({ page }) => {
    const renders = await expectDbBudget(page, {
      during: async () => {
        await page.goto(entry.url);
        await expect(
          page.getByRole("heading", { level: 1 }).first(),
        ).toBeVisible();
      },
      maxCalls: entry.maxCalls,
      maxWaves: entry.maxWaves,
    });

    const measured = renders.reduce(
      (worst, render) => ({
        calls: Math.max(worst.calls, render.stats.calls),
        waves: Math.max(worst.waves, render.stats.waves),
      }),
      { calls: 0, waves: 0 },
    );

    recordPerf("budgets.json", entry.route, measured);
  });
}
