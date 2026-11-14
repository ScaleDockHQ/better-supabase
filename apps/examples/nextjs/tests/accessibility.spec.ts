/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
/* oxlint-disable vitest/prefer-each -- Playwright has no test.each; the loop
   generates one case per declared page (1 finding). */
import { AxeBuilder } from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

import { pageCoverage } from "../src/lib/supabase/pages/coverage";
import { signIn } from "./support/example-session";

// One axe pass per route of a declared entity page, generated from
// `pages/coverage.ts`. Only serious and critical findings fail, so the check
// guards the generated tables, filters and forms without gating on advice.

const declaredRoutes = [
  ...new Set(Object.values(pageCoverage).flat()),
].toSorted();

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

for (const route of declaredRoutes) {
  test(`${route} has no serious accessibility violations`, async ({ page }) => {
    await page.goto(route);
    await page.locator("main").waitFor();

    const results = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
      .analyze();

    const blocking = results.violations
      .filter(
        (violation) =>
          violation.impact === "serious" || violation.impact === "critical",
      )
      .map((violation) => ({
        id: violation.id,
        impact: violation.impact,
        nodes: violation.nodes.slice(0, 3).map((node) => node.target.join(" ")),
      }));

    expect(blocking).toEqual([]);
  });
}
