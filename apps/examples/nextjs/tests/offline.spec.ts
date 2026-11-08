/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import type { Page } from "@playwright/test";

import { expect, test } from "@playwright/test";

async function signIn(page: Page): Promise<void> {
  await page.goto("/en/login");
  await page.getByLabel("Email").fill("admin@acme.test");
  await page.getByLabel("Password").fill("password123");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL((url) => !url.pathname.endsWith("/login"));
}

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("a loaded list keeps its rows while offline and the banner follows the connection", async ({
  page,
  context,
}) => {
  await page.goto("/en/customers");
  await expect(page.getByText("Road Runner Inc")).toBeVisible();

  const banner = page.getByText("You are offline");

  await expect(banner).toBeHidden();

  await context.setOffline(true);
  await expect(banner).toBeVisible();
  await expect(page.getByText("Road Runner Inc")).toBeVisible();

  await context.setOffline(false);
  await expect(banner).toBeHidden();
  await expect(page.getByText("Road Runner Inc")).toBeVisible();
});
