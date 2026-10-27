/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import type { Page } from "@playwright/test";

import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

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

test("home to customers renders the static shell under the lock", async ({
  page,
}) => {
  await page.goto("/en");
  const link = page.getByRole("link", { name: "Customers", exact: true });

  await expect(link.first()).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.first().click();
      await page.waitForURL((url) => url.pathname === "/en/customers");
    },
    visible: [page.getByRole("heading", { name: "Customers" })],
  });

  await expect(page.getByText("Road Runner Inc")).toBeVisible();
});

test("customers to a customer uses the per-link prefetch", async ({ page }) => {
  await page.goto("/en/customers");
  const link = page.getByRole("link", { name: "Road Runner Inc" });

  await expect(link).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) => url.pathname.startsWith("/en/customers/"));
    },
    visible: [page.getByRole("link", { name: "All customers" })],
  });
});

test("settings tab to tab keeps the settings frame", async ({ page }) => {
  await page.goto("/en/settings/profile");
  const tab = page.getByRole("link", { name: "Preferences", exact: true });

  await expect(tab).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await tab.click();
      await page.waitForURL(
        (url) => url.pathname === "/en/settings/preferences",
      );
    },
    visible: [page.getByRole("heading", { name: "Settings" })],
  });
});
