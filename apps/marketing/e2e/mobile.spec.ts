import { AxeBuilder } from "@axe-core/playwright";
import { expect, type Page, test } from "@playwright/test";

const PAGES = [
  "/",
  "/blocks",
  "/blocks/notifications",
  "/recipes",
  "/recipes/notification-bell",
  "/enterprise",
] as const;

const WCAG = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

async function scrollsSideways(page: Page): Promise<boolean> {
  return page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth,
  );
}

test("the menu button opens the main nav and a link navigates", async ({
  page,
}) => {
  await page.goto("/");

  const trigger = page
    .getByRole("banner")
    .getByRole("button", { name: "Open menu" });

  await expect(trigger).toHaveAttribute("aria-expanded", "false");
  await trigger.click();
  // The open sheet makes the page inert, which hides the trigger from role queries.
  await expect(
    page.locator("header button[aria-label='Open menu']"),
  ).toHaveAttribute("aria-expanded", "true");

  const menu = page.getByRole("dialog", { name: "Menu" });

  await expect(menu.getByRole("link", { name: "GitHub" })).toHaveAttribute(
    "href",
    /github\.com/,
  );
  await expect(menu.getByRole("link", { name: "Get started" })).toBeVisible();
  await expect(menu.getByRole("link", { name: "Sign in" })).toHaveAttribute(
    "href",
    "https://app.bettersupabase.com/sign-in",
  );

  await menu.getByRole("link", { name: "Blocks", exact: true }).click();

  await expect(page).toHaveURL(/\/blocks$/);
  await expect(menu).toBeHidden();

  await trigger.click();
  await expect(
    page
      .getByRole("dialog", { name: "Menu" })
      .getByRole("link", { name: "Blocks", exact: true }),
  ).toHaveAttribute("aria-current", "page");
});

test("the menu closes on the back button", async ({ page }) => {
  await page.goto("/enterprise");
  await page.goto("/recipes");

  await page.getByRole("button", { name: "Open menu" }).click();
  await expect(page.getByRole("dialog", { name: "Menu" })).toBeVisible();

  await page.goBack();

  await expect(page).toHaveURL(/\/enterprise$/);
  await expect(page.getByRole("dialog", { name: "Menu" })).toBeHidden();
});

for (const colorScheme of ["light", "dark"] as const) {
  test(`the open menu has no WCAG 2.2 AA violations in the ${colorScheme} theme`, async ({
    page,
  }) => {
    await page.emulateMedia({ colorScheme });
    await page.goto("/blocks");
    await page.getByRole("button", { name: "Open menu" }).click();

    const menu = page.getByRole("dialog", { name: "Menu" });

    await expect(menu).toBeVisible();
    await expect(menu).toHaveCSS("opacity", "1");

    const { violations } = await new AxeBuilder({ page })
      .include("[data-slot='sheet-content']")
      .withTags(WCAG)
      .analyze();

    expect(
      violations.map((violation) => ({
        id: violation.id,
        targets: violation.nodes.map((node) => node.target.join(" ")),
      })),
    ).toEqual([]);
  });
}

test("the blocks sheet opens and a link closes it", async ({ page }) => {
  await page.goto("/blocks/notifications");

  await page.getByRole("button", { name: "Browse blocks" }).click();

  const sheet = page.getByRole("dialog");

  await expect(sheet).toBeVisible();
  await sheet.getByRole("link", { name: "RLS on every new table" }).click();

  await expect(page).toHaveURL(/\/blocks\/ensure-rls$/);
  await expect(sheet).toBeHidden();
});

for (const width of [375, 768]) {
  test.describe(`at ${String(width)}px`, () => {
    test.use({ viewport: { width, height: 812 } });

    for (const path of PAGES) {
      test(`${path} does not scroll sideways`, async ({ page }) => {
        await page.goto(path);
        await page.waitForLoadState("load");

        expect(await scrollsSideways(page)).toBe(false);
      });
    }
  });
}
