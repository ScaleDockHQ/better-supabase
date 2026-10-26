import { test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

test("the blocks page is instant from the navbar", async ({ page }) => {
  await page.goto("/");

  await expectInstant(page, {
    during: async () => {
      await page
        .getByRole("navigation", { name: "Main" })
        .getByRole("link", { name: "Blocks", exact: true })
        .click();
      await page.waitForURL((url) => url.pathname === "/blocks");
    },
    visible: [
      page.getByRole("heading", { name: "Pick the features your app needs" }),
    ],
  });
});
