/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import type { Page } from "@playwright/test";

import { instant } from "@next/playwright";
import { expect, test } from "@playwright/test";

// Each test states which content is visible before uncached work resolves
// (under `instant()`'s lock) and which streams in after it. They need a `next
// build` with the testing API exposed, like instant.spec.ts, and the local
// Supabase stack with the seeded users.

async function signIn(page: Page): Promise<void> {
  await page.goto("/en/login");
  await page.getByLabel("Email").fill("admin@acme.test");
  await page.getByLabel("Password").fill("password123");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL((url) => !url.pathname.endsWith("/login"));
}

test("the customers list paints its heading before the rows", async ({
  page,
}) => {
  await signIn(page);
  await page.goto("/en");
  const link = page.getByRole("link", { name: "Customers", exact: true });

  await expect(link.first()).toBeVisible();

  await instant(page, async () => {
    await link.first().click();
    await page.waitForURL((url) => url.pathname === "/en/customers");

    await expect(
      page.getByRole("heading", { name: "Customers" }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: "Road Runner Inc" }),
    ).toHaveCount(0);
  });

  await expect(
    page.getByRole("link", { name: "Road Runner Inc" }),
  ).toBeVisible();
});

test("a customer shows its head before the side sections", async ({ page }) => {
  await signIn(page);
  await page.goto("/en/customers");
  const row = page.getByRole("link", { name: "Road Runner Inc" });

  await expect(row).toBeVisible();

  await instant(page, async () => {
    await row.click();
    await page.waitForURL((url) => url.pathname.startsWith("/en/customers/"));

    await expect(
      page.getByRole("link", { name: "All customers" }),
    ).toBeVisible();
    // The versions and timeline cards await navigation(), so the per-link
    // prefetch leaves them out of the locked render.
    await expect(page.getByText("Version history")).toHaveCount(0);
    await expect(page.getByText("Timeline", { exact: true })).toHaveCount(0);
  });

  await expect(page.getByText("Version history")).toBeVisible();
  await expect(page.getByText("Timeline", { exact: true })).toBeVisible();
});

test("the sign-in form is static and the sign-up link is instant", async ({
  page,
}) => {
  await page.goto("/en/login");
  const signUp = page.getByRole("link", { name: "Sign up" });

  await expect(signUp).toBeVisible();

  await instant(page, async () => {
    await signUp.click();
    await page.waitForURL((url) => url.pathname === "/en/signup");

    await expect(page.getByLabel("Email")).toBeVisible();
  });
});
