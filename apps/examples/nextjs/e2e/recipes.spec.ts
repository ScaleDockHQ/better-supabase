/**
 * Every recipe route renders its recipe, and nothing on the page failed to
 * load. The region is the element with `data-recipe="<slug>"`, the one
 * `recipe-screenshots.spec.ts` captures.
 */
import { expect, test } from "@playwright/test";

import { RECIPE_ROUTES } from "./recipe-routes";
import { users } from "./users";

test.use({ storageState: users.admin.storageState });

for (const route of RECIPE_ROUTES) {
  test(`${route.slug} renders on ${route.path}`, async ({ page }) => {
    await page.goto(route.path);
    await route.prepare?.(page);

    const region =
      route.region?.(page) ??
      page.locator(`[data-recipe="${route.slug}"]`).filter({ visible: true });

    await expect(region.first()).toBeVisible();
    await expect(page.getByRole("button", { name: "Retry" })).toHaveCount(0);
  });
}
