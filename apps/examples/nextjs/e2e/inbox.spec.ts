import { instant } from "@next/playwright";
import { expect, test } from "@playwright/test";

import { heading, sidebarLink } from "./nav";
import { users } from "./users";

test.use({ storageState: users.admin.storageState });

test("the inbox shell commits and the server count streams in", async ({
  page,
}) => {
  await page.goto("/");
  await expect(sidebarLink(page, "Inbox")).toBeVisible();
  await instant(page, async () => {
    await sidebarLink(page, "Inbox").click();
    await page.waitForURL((url) => url.pathname === "/inbox");
    await expect(heading(page, "Inbox")).toBeVisible();
    // Uncached on purpose: the seed must be as fresh as the live channel.
    await expect(page.getByTestId("unread-summary")).toHaveCount(0);
  });
  await expect(page.getByTestId("unread-summary")).toBeVisible();
});
