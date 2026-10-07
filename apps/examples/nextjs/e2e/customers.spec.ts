import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import { clickSidebar, heading, sidebarLink } from "./nav";
import { users } from "./users";

test.use({ storageState: users.admin.storageState });

test("customers come from the per-session App Shell on a click", async ({
  page,
}) => {
  await page.goto("/");
  await expect(sidebarLink(page, "Customers")).toBeVisible();
  await expectInstant(page, {
    during: clickSidebar(page, "Customers", "/customers"),
    visible: [
      heading(page, "Customers"),
      page.getByText("Road Runner Inc"),
      page.getByTestId("similar-notes"),
    ],
    maxCalls: 8,
    maxWaves: 2,
  });
});

test("a new customer shows on the next visit", async ({ page }) => {
  const name = `AAA e2e ${String(Date.now())}`;
  await page.goto("/customers");
  await page.getByPlaceholder("New customer").fill(name);
  await page.getByRole("button", { name: "Add" }).click();
  await expect(page.getByText(name)).toBeVisible();

  await sidebarLink(page, "Dashboard").click();
  await page.waitForURL((url) => url.pathname === "/");
  await sidebarLink(page, "Customers").click();
  await page.waitForURL((url) => url.pathname === "/customers");
  await expect(page.getByText(name)).toBeVisible();

  await page.reload();
  await expect(page.getByText(name)).toBeVisible();
});
