import { AxeBuilder } from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const WCAG = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

test.use({ colorScheme: "light" });

test("pressing D switches the theme", async ({ page }) => {
  await page.goto("/");
  await page.waitForLoadState("load");

  const html = page.locator("html");

  await expect(html).not.toHaveClass(/\bdark\b/);
  await page.locator("body").press("d");
  await expect(html).toHaveClass(/\bdark\b/);
  await page.locator("body").press("d");
  await expect(html).not.toHaveClass(/\bdark\b/);
});

test("typing D in a field or with a modifier keeps the theme", async ({
  page,
}) => {
  await page.goto("/blocks");
  await page.waitForLoadState("load");

  const html = page.locator("html");
  const search = page.getByRole("searchbox").first();

  await search.press("d");
  await expect(search).toHaveValue("d");
  await page.locator("body").press("Shift+D");

  await expect(html).not.toHaveClass(/\bdark\b/);
});

test("the GitHub link in the navbar has a name", async ({ page }) => {
  await page.goto("/");

  await expect(
    page.getByRole("banner").getByRole("link", { name: "GitHub repository" }),
  ).toHaveAttribute("href", /github\.com/);
});

test("the current section is marked in the navbar", async ({ page }) => {
  await page.goto("/blocks/notifications");

  await expect(
    page.getByRole("navigation", { name: "Main" }).getByRole("link", {
      name: "Blocks",
    }),
  ).toHaveAttribute("aria-current", "page");
});

test("the logo cloud links each integration to its docs", async ({ page }) => {
  await page.goto("/");

  await expect(
    page.getByRole("link", { name: "Hono", exact: true }),
  ).toHaveAttribute("href", "/docs/frameworks/hono");
});

for (const colorScheme of ["light", "dark"] as const) {
  test.describe(`${colorScheme} theme`, () => {
    test.use({ colorScheme });

    test("the home page chrome has no WCAG 2.2 AA violations", async ({
      page,
    }) => {
      await page.goto("/");
      await page.waitForLoadState("load");

      const { violations } = await new AxeBuilder({ page })
        .include("header")
        .include("#frameworks")
        .include("footer")
        .withTags(WCAG)
        .analyze();

      expect(
        violations.map((violation) => ({
          id: violation.id,
          targets: violation.nodes.map((node) => node.target.join(" ")),
        })),
      ).toEqual([]);
    });
  });
}
