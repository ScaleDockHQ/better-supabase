import { instant } from "@next/playwright";
import { expect, test } from "@playwright/test";

import { heading, sidebarLink } from "./nav";
import { users } from "./users";

test.use({ storageState: users.admin.storageState });

test("Reports passes its permission gate from the cached session", async ({
  page,
}) => {
  await page.goto("/");
  await expect(sidebarLink(page, "Reports")).toBeVisible();
  await instant(page, async () => {
    await sidebarLink(page, "Reports").click();
    await page.waitForURL((url) => url.pathname === "/reports");
    await expect(heading(page, "Reports")).toBeVisible();
    await expect(page.getByText("Revenue and pipeline reports.")).toBeVisible();
  });
});

test("Billing shows the plan features from the cached session", async ({
  page,
}) => {
  await page.goto("/");
  await expect(sidebarLink(page, "Billing")).toBeVisible();
  await instant(page, async () => {
    await sidebarLink(page, "Billing").click();
    await page.waitForURL((url) => url.pathname === "/billing");
    await expect(heading(page, "Billing")).toBeVisible();
    await expect(
      page.getByRole("list", { name: "Plan features" }),
    ).toBeVisible();
  });
});
