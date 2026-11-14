/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import { expect, test } from "@playwright/test";

import { signIn } from "./support/example-session";

// The marketplace read goes through the member-readable
// `marketplace_installation_for`; the Stripe routes answer without keys.

test("the marketplace page lists the linked installation and opens a resource", async ({
  page,
}) => {
  await signIn(page);
  await page.goto("/settings/marketplace");

  await expect(page.getByText("icfg_acme_demo")).toBeVisible();

  await page.getByRole("link", { name: "Primary database" }).click();

  await expect(
    page.getByRole("heading", { name: "Primary database" }),
  ).toBeVisible();
  await expect(page.getByText("res_acme_primary")).toBeVisible();
  await expect(page.getByText("team_acme_demo")).toBeVisible();
});

test("an unknown marketplace resource shows the not-found page", async ({
  page,
}) => {
  await signIn(page);

  await page.goto("/settings/marketplace/res_missing");

  await expect(page.getByText("Page not found")).toBeVisible();
});

test("the Stripe webhook and process routes refuse without their secrets", async ({
  request,
}) => {
  const process = await request.get("/api/stripe/process");

  expect(process.status()).toBe(401);

  const webhook = await request.post("/api/stripe", { data: "{}" });

  expect([400, 401, 503]).toContain(webhook.status());
});
