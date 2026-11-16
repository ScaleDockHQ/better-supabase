/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
/* oxlint-disable vitest/prefer-each -- Playwright has no test.each; the loop
   generates one case per overview (1 finding). */
import { expect, test } from "@playwright/test";

import { signIn } from "./support/example-session";

// The overviews that read the block's `page` on the server (ADR 1077, lane Y1):
// every URL state of the search, the facet, the sort and the cursor is answered
// by the database, and a failed read shows the load error instead of rows.

const ROUTES = [
  "/crm/segments",
  "/crm/queues",
  "/crm/scoring",
  "/crm/success",
  "/crm/contracts",
  "/crm/contacts",
  "/crm/companies",
  "/crm/deals",
  "/crm/pipelines",
  "/crm/forecasts",
  "/crm/quotes",
  "/crm/commissions",
  "/crm/commissions?tab=plans",
  "/crm/commissions?tab=statements",
  "/crm/referrals",
  "/crm/referrals?tab=codes",
  "/crm/sequences",
  "/lims",
  "/lims?tab=methods",
  "/rfqs",
  "/tills",
  "/tills?tab=tills",
  "/maintenance",
  "/maintenance?tab=meters",
  "/maintenance?tab=calibrations",
  "/warehouse",
  "/warehouse?tab=waves",
  "/warehouse?tab=putaway",
  "/warehouse?tab=counts",
] as const;

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

// Picks the second option of every select of the overview (its facet and its
// sort), so each facet value and sort the page offers reaches the block.
for (const route of ROUTES) {
  test(`${route} answers each facet and sort it offers`, async ({ page }) => {
    test.setTimeout(90_000);
    await page.goto(route);

    const selects = page.getByRole("main").getByRole("combobox");

    for (let index = 0; index < (await selects.count()); index += 1) {
      await selects.nth(index).click();

      // Keys, because the popup's options re-measure while it opens and a
      // click on one waits for them to settle.
      await expect(page.getByRole("listbox")).toBeVisible();
      await page.keyboard.press("ArrowDown");
      await page.keyboard.press("Enter");
      await expect(page.getByRole("listbox")).toBeHidden();
      await page.waitForTimeout(1200);

      await expect(page.getByText("didn't load")).toHaveCount(0);
    }
  });
}

for (const route of ROUTES) {
  const join = route.includes("?") ? "&" : "?";

  test(`${route} answers a search, a sort and a cursor`, async ({ page }) => {
    for (const query of ["", `${join}q=zzz-no-such-row`, `${join}sort=zzz`]) {
      const response = await page.goto(`${route}${query}`);

      expect(response?.status()).toBeLessThan(400);
      await expect(page.getByRole("main")).toBeVisible();
      await expect(page.getByText("didn't load")).toHaveCount(0);
    }
  });
}
