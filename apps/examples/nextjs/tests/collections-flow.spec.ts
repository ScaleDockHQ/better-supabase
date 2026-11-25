/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import { expect, test } from "@playwright/test";

import { signIn } from "./support/example-session";

// The seed sets three reminder levels and runs dunning once, so the invoices
// page shows both tables of its Collections section.

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("the invoices page lists the reminder levels and the latest run", async ({
  page,
}) => {
  await page.goto("/finance/invoices");

  const main = page.getByRole("main");

  const levels = main
    .getByRole("table")
    .filter({
      has: page.getByRole("columnheader", { name: "Days after due" }),
    });

  await expect(levels.getByRole("row")).toHaveCount(4);
  await expect(levels.getByText("Final notice")).toBeVisible();

  const runs = main
    .getByRole("table")
    .filter({ has: page.getByRole("columnheader", { name: "As of" }) });

  await expect(runs.getByRole("row").nth(1)).toBeVisible();
});
