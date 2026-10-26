import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

const baseURL = "http://127.0.0.1:3002";

test("a docs article is instant on an initial load", async ({ page }) => {
  const heading = page.getByRole("heading", {
    level: 1,
    name: "Cache Components",
  });

  await expectInstant(page, {
    during: () => page.goto("/docs/frameworks/next-cache-components"),
    visible: [heading],
    baseURL,
  });

  await expect(heading).toBeVisible();
});
