import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import { clickSidebar, heading, sidebarLink } from "./nav";
import { users } from "./users";

test.use({ storageState: users.admin.storageState });

test("Reports passes its permission gate from the cached session", async ({
  page,
}) => {
  await page.goto("/");
  await expect(sidebarLink(page, "Reports")).toBeVisible();
  await expectInstant(page, {
    during: clickSidebar(page, "Reports", "/reports"),
    visible: [
      heading(page, "Reports"),
      page.getByText("Revenue and pipeline reports."),
    ],
  });
});

test("Billing shows the plan features from the cached session", async ({
  page,
}) => {
  await page.goto("/");
  await expect(sidebarLink(page, "Billing")).toBeVisible();
  await expectInstant(page, {
    during: clickSidebar(page, "Billing", "/billing"),
    visible: [
      heading(page, "Billing"),
      page.getByRole("list", { name: "Plan features" }),
    ],
  });
});
