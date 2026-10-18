import { expect, test } from "@playwright/test";

test.use({ viewport: { width: 1440, height: 900 } });

test("the blocks sidebar hides the native scrollbar and shows the current block", async ({
  page,
}) => {
  await page.goto("/blocks/ensure-rls");

  const sidebar = page.getByRole("navigation", { name: "Blocks" }).first();

  const viewport = page
    .locator("aside [data-slot='scroll-area-viewport']")
    .first();

  await expect(sidebar).toBeVisible();
  await expect
    .poll(() =>
      viewport.evaluate((node) => getComputedStyle(node).scrollbarWidth),
    )
    .toBe("none");

  const current = sidebar.locator('[aria-current="page"]');

  await expect(current).toHaveText("RLS on every new table");
  await expect(current).toBeInViewport();
});
