/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
/* oxlint-disable vitest/prefer-each -- Playwright has no test.each; the loop
   generates one case per route of the manifest (1 finding). */
import { test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import { ROUTES } from "./routes.manifest";
import { openableRoutes, pushRoute, signIn } from "./support/example-session";

// One case per route that exports `instant = true`, generated from the route
// manifest: a client navigation from the dashboard paints the page's first
// heading under the instant lock and stays inside the route's database budget.
// Needs the production build with the testing API (see instant-nav.rig.md).

const instantRoutes = openableRoutes(ROUTES).filter((entry) => entry.instant);

test.beforeEach(async ({ page }) => {
  await signIn(page);
  await page.goto("/");
});

for (const entry of instantRoutes) {
  test(`${entry.route} navigates instantly`, async ({ page }) => {
    await expectInstant(page, {
      during: () => pushRoute(page, entry.url),
      visible: [page.getByRole("heading", { level: 1 }).first()],
      maxCalls: entry.maxCalls,
      maxWaves: entry.maxWaves,
    });
  });
}
