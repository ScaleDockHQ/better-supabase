import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import { clickSidebar, heading, sidebarLink } from "./nav";
import { users } from "./users";

test.use({ storageState: users.admin.storageState });

test("the inbox shell commits and the server count streams in", async ({
  page,
}) => {
  await page.goto("/");
  await expect(sidebarLink(page, "Inbox")).toBeVisible();
  await expectInstant(page, {
    during: clickSidebar(page, "Inbox", "/inbox"),
    visible: [heading(page, "Inbox")],
    // Uncached on purpose: the seed must be as fresh as the live channel.
    absent: [page.getByTestId("unread-summary")],
  });
  await expect(page.getByTestId("unread-summary")).toBeVisible();
});
