/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import type { Page } from "@playwright/test";

import { expect, test } from "@playwright/test";

// The risk register reads its URL state through the generated `risksList`
// (ADR 0859), and `/api/risks/list` and `/api/work-orders/list` are generated
// routes. Needs the local stack with the seeded users and `pnpm db:seed:pages`.

async function signIn(page: Page): Promise<void> {
  await page.goto("/login");
  await page.getByRole("textbox", { name: "Email" }).fill("admin@acme.test");
  await page.getByLabel("Password").fill("password123");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL((url) => !url.pathname.endsWith("/login"));
}

// A cold server streams the register once into a hidden boundary before it swaps in,
// so the visible list is the one inside the page's main region.
const register = (page: Page) =>
  page.getByRole("main").getByTestId("record-list");

test("the register sorts by a declared sort and writes it to the URL", async ({
  page,
}) => {
  await signIn(page);
  await page.goto("/risks");
  await expect(register(page)).toBeVisible();

  await page.getByRole("combobox", { name: "Sort by" }).click();
  await page.getByRole("option", { name: "Number" }).click();

  await expect(page).toHaveURL(/[?&]sort=number/);
  await expect(register(page)).toBeVisible();

  await page.getByRole("combobox", { name: "Sort by" }).click();
  await page.getByRole("option", { name: "Residual score" }).click();

  await expect(page).not.toHaveURL(/[?&]sort=number/);
});

test("an unfinished filter rule stays in the chips while the URL changes", async ({
  page,
}) => {
  await signIn(page);
  await page.goto("/risks");
  await expect(register(page)).toBeVisible();

  await page.getByRole("button", { name: "Add filter" }).click();
  await page.getByRole("option", { name: "Status" }).click();

  // The rule has a field and no value yet, so it is not in the URL.
  await expect(page).not.toHaveURL(/[?&]status=/);

  await page.getByRole("combobox", { name: "Sort by" }).click();
  await page.getByRole("option", { name: "Number" }).click();
  await expect(page).toHaveURL(/[?&]sort=number/);

  await expect(page.getByText("Status", { exact: true }).first()).toBeVisible();
});

test("the generated list routes answer a page with its facets", async ({
  page,
}) => {
  await signIn(page);

  const risks = await page.request.get("/api/risks/list?sort=number");

  expect(risks.status()).toBe(200);
  expect(await risks.text()).toContain("facets");

  const refused = await page.request.get("/api/risks/list?sort=bogus");

  expect(refused.status()).toBe(400);

  const orders = await page.request.get("/api/work-orders/list");

  expect(orders.status()).toBe(200);
  expect(await orders.text()).toContain("Title 1");
});
