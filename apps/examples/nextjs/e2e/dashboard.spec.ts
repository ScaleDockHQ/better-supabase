import { instant } from "@next/playwright";
import { expect, test } from "@playwright/test";

import { heading } from "./nav";
import { baseURL } from "./server";
import { users } from "./users";

test.use({ storageState: users.admin.storageState });

test("the dashboard's static shell is served on an initial load", async ({
  page,
}) => {
  await instant(
    page,
    async () => {
      await page.goto("/");
      await expect(heading(page, "Dashboard")).toBeVisible();
      await expect(
        page.getByRole("navigation", { name: "Main" }),
      ).toHaveAttribute("aria-busy", "true");
      // The summary reads the session, so it is never in the static shell.
      await expect(page.getByTestId("workspace-summary")).toHaveCount(0);
    },
    { baseURL },
  );
  await expect(page.getByTestId("workspace-summary")).toBeVisible();
});
