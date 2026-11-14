/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import { expect, test } from "@playwright/test";

import { signIn } from "./support/example-session";

// `?new=1` is the link the command center uses to land on a page with its
// create dialog open; the seeded admin owns Acme, so it may create all three.

test("/crm/contacts?new=1 opens the create dialog", async ({ page }) => {
  await signIn(page);
  await page.goto("/crm/contacts?new=1");

  await expect(page.getByRole("dialog", { name: "Add contact" })).toBeVisible();
});

test("/crm/deals?new=1 opens the create dialog", async ({ page }) => {
  await signIn(page);
  await page.goto("/crm/deals?new=1");

  await expect(page.getByRole("dialog", { name: "Add deal" })).toBeVisible();
});

test("/crm/quotes?new=1 opens the create dialog", async ({ page }) => {
  await signIn(page);
  await page.goto("/crm/quotes?new=1");

  await expect(page.getByRole("dialog", { name: "New quote" })).toBeVisible();
});

test("the command palette lists the create actions for an owner", async ({
  page,
}) => {
  await signIn(page);
  await page.goto("/crm/contacts");
  // The palette loads on the first intent; let the page hydrate so the
  // shortcut listener exists before the key press.
  await page.waitForLoadState("networkidle");
  await page.keyboard.press("Control+K");

  for (const name of ["New contact", "New deal", "New quote"]) {
    await expect(page.getByRole("option", { name, exact: true })).toBeVisible();
  }
});
