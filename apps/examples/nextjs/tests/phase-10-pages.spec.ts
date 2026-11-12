/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import { expect, test } from "@playwright/test";

import { signIn } from "./support/example-session";

// The write paths of the pages the follow-up added: each one saves through its
// action and shows the row again from the tagged read. They need the local stack
// with the seeded users, and no testing API.

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("a content draft is saved and published", async ({ page }) => {
  const slug = `hello-${Date.now()}`;

  await page.goto("/content");
  await page.getByRole("button", { name: "New entry" }).click();
  await page.getByLabel("Title").fill(`Entry ${slug}`);
  await page.getByLabel("Slug").fill(slug);
  await page.getByRole("button", { name: "Save draft" }).click();

  const row = page.getByRole("row", { name: new RegExp(slug) });
  await expect(row).toBeVisible();
  await expect(row.getByText("Draft")).toBeVisible();

  await row.getByRole("button", { name: "Publish" }).click();
  await expect(row.getByText("Published")).toBeVisible();
});

test("an advisories product is added", async ({ page }) => {
  const key = `cli-${Date.now()}`;

  await page.goto("/advisories");
  await page.getByRole("button", { name: "Add product" }).click();
  await page.getByLabel("Name").fill(`Product ${key}`);
  await page.getByLabel("Key").fill(key);
  await page.getByRole("button", { name: "Save product" }).click();

  await expect(page.getByText(`Product ${key}`)).toBeVisible();
});

test("a chat link code is issued on the security page", async ({ page }) => {
  await page.goto("/settings/security");
  await page.getByRole("button", { name: "Get link code" }).click();

  await expect(page.getByText("Send this code to the bot:")).toBeVisible();
});

test("the content page reads in Dutch", async ({ page }) => {
  await page.goto("/nl/content");

  await expect(page.getByRole("heading", { name: "Inhoud" })).toBeVisible();
});
