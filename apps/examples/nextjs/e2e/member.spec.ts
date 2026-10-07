import { instant } from "@next/playwright";
import { expect, test } from "@playwright/test";

import { heading, sidebarLink } from "./nav";
import { users } from "./users";

test.use({ storageState: users.member.storageState });

test("a member's customers come from the App Shell, without write access", async ({
  page,
}) => {
  await page.goto("/");
  await expect(sidebarLink(page, "Customers")).toBeVisible();
  await instant(page, async () => {
    await sidebarLink(page, "Customers").click();
    await page.waitForURL((url) => url.pathname === "/customers");
    await expect(heading(page, "Customers")).toBeVisible();
    await expect(page.getByText("Road Runner Inc")).toBeVisible();
    await expect(
      page.getByText("Only admins can add customers."),
    ).toBeVisible();
  });
});

test("a member doesn't see or reach admin pages", async ({ page }) => {
  await page.goto("/");
  await expect(sidebarLink(page, "Customers")).toBeVisible();
  for (const label of ["Reports", "Users", "Billing", "Audit log", "Settings"])
    await expect(sidebarLink(page, label)).toHaveCount(0);
  await page.goto("/users");
  await expect(page).toHaveURL((url) => url.pathname === "/");
});
