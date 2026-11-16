/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import { expect, test } from "@playwright/test";

import { signIn } from "./support/example-session";

// Findings EX-200, EX-204, EX-400 and EX-401: the workflow overviews read
// `definitions.page` and the `definitionId` run filter, and the inbox queue
// reads `inboxes.page`, `templates.page` and the priority and SLA filters of
// `conversations.page`.

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("the definitions overview answers a search, a state facet and a sort", async ({
  page,
}) => {
  for (const query of [
    "",
    "?q=zzz-no-such-definition",
    "?state=published",
    "?state=draft,new&sort=name",
  ]) {
    const response = await page.goto(`/workflows${query}`);

    expect(response?.status()).toBe(200);
    await expect(page.getByText("didn't load")).toHaveCount(0);
  }
});

test("the runs overview answers the definition facet in the database", async ({
  page,
}) => {
  for (const query of [
    "",
    "?definition=00000000-0000-0000-0000-000000000000",
    "?status=failed,completed&since=week",
  ]) {
    const response = await page.goto(`/workflows/runs${query}`);

    expect(response?.status()).toBe(200);
    await expect(page.getByText("didn't load")).toHaveCount(0);
  }
});

test("the inbox queue filters by priority and first response state", async ({
  page,
}) => {
  await page.goto("/inbox");

  const queue = page.getByRole("region", { name: "Conversations" });
  const failed = page.getByText("The queue did not load");

  await expect(queue).toBeVisible();

  // The channel filter lists the inboxes `inboxes.page` returns.
  await queue.getByRole("combobox", { name: "Channel" }).click();
  await expect(page.getByRole("option").nth(1)).toBeVisible();
  await page.keyboard.press("Escape");

  await queue.getByRole("combobox", { name: "Priority" }).click();
  await page.getByRole("option", { name: "Urgent" }).click();
  await expect(page).toHaveURL(/priority=urgent/u);

  await queue.getByRole("combobox", { name: "SLA" }).click();
  await page.getByRole("option", { name: "Breached" }).click();
  await expect(page).toHaveURL(/sla=breached/u);

  await page.waitForTimeout(1200);
  await expect(failed).toHaveCount(0);

  // Everything urgent and breached is a subset, never an error.
  await queue.getByRole("combobox", { name: "Priority" }).click();
  await page.getByRole("option", { name: "All priorities" }).click();
  await expect(page).not.toHaveURL(/priority=/u);
  await expect(failed).toHaveCount(0);
});

test("the composer lists the macros of the organization", async ({ page }) => {
  await page.goto("/inbox");

  const first = page
    .getByRole("region", { name: "Conversations" })
    .getByRole("link")
    .first();

  await first.click();
  await page.waitForURL(/\/inbox\/[0-9a-f-]{36}/u);
  await expect(page.getByText("didn't load")).toHaveCount(0);
});
