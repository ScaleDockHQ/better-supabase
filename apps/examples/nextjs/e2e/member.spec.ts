import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import { clickSidebar, heading, sidebarLink } from "./nav";
import { users } from "./users";

test.use({ storageState: users.member.storageState });

test("a member's customers come from the App Shell, without write access", async ({
  page,
}) => {
  await page.goto("/");
  await expect(sidebarLink(page, "Customers")).toBeVisible();
  await expectInstant(page, {
    during: clickSidebar(page, "Customers", "/customers"),
    visible: [
      heading(page, "Customers"),
      page.getByText("Road Runner Inc"),
      page.getByText("Only admins can add customers."),
    ],
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
