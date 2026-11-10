/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import type { Page } from "@playwright/test";

import { instant } from "@next/playwright";
import { expect, test } from "@playwright/test";

// Runs only after `pnpm db:seed:scale` (5M audit events, 1M recipients), with
// `playwright test --grep @scale` and a `next build` that exposes the testing API.

async function signIn(page: Page): Promise<void> {
  await page.goto("/login");
  await page.getByRole("textbox", { name: "Email" }).fill("admin@acme.test");
  await page.getByLabel("Password").fill("password123");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL((url) => !url.pathname.endsWith("/login"));
}

test.describe("@scale audit log", () => {
  test("paints the card and filter bar before the rows", async ({ page }) => {
    await signIn(page);
    await page.goto("/settings");

    await instant(page, async () => {
      await page.goto("/settings/audit");
      await expect(page.getByTestId("audit-events")).toHaveCount(0);
    });

    await expect(page.getByTestId("audit-events")).toBeVisible();
  });

  test("keeps every page at 50 rows through three Older links", async ({
    page,
  }) => {
    await signIn(page);
    await page.goto("/settings/audit");

    for (let step = 0; step < 3; step += 1) {
      await expect(
        page.getByTestId("audit-events").locator("tbody tr"),
      ).toHaveCount(50);
      await page.getByRole("link", { name: "Older" }).click();
      await page.waitForURL(/before=/);
    }
  });

  test("an actor filter updates the URL and the rows, and an entry opens its details", async ({
    page,
  }) => {
    await signIn(page);
    await page.goto("/settings/audit");
    await page.getByRole("combobox", { name: "Actor" }).click();
    await page.getByRole("option").nth(1).click();
    await page.waitForURL(/actor=/);
    await expect(page.getByTestId("audit-events")).toBeVisible();

    await page.getByTestId("audit-events").locator("tbody a").first().click();
    await page.waitForURL(/entry=/);
    await expect(page.getByRole("dialog")).toBeVisible();
  });
});

test.describe("@scale notifications", () => {
  test("pages through the 200,000-row inbox 20 rows at a time", async ({
    page,
  }) => {
    await signIn(page);
    await page.goto("/notifications");

    await expect(
      page.getByTestId("notification-rows").locator("li"),
    ).toHaveCount(20);
    await page.getByRole("link", { name: "Older" }).click();
    await page.waitForURL(/before=/);
    await expect(
      page.getByTestId("notification-rows").locator("li"),
    ).toHaveCount(20);
  });

  test("shows a capped badge", async ({ page }) => {
    await signIn(page);
    await page.goto("/notifications");
    await expect(page.getByTestId("unread-count")).toHaveText("99+");
  });
});
