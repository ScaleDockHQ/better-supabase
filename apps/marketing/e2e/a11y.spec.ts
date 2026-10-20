import { AxeBuilder } from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const PAGES = [
  "/",
  "/blocks",
  "/blocks/notifications",
  "/recipes",
  "/recipes/notification-bell",
  "/enterprise",
] as const;

const WCAG = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

for (const colorScheme of ["light", "dark"] as const) {
  test.describe(`${colorScheme} theme`, () => {
    test.use({ colorScheme });

    for (const path of PAGES) {
      test(`${path} has no WCAG 2.2 AA violations`, async ({ page }) => {
        await page.goto(path);
        await page.waitForLoadState("load");

        const { violations } = await new AxeBuilder({ page })
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
  });
}

test.describe("at 360px", () => {
  test.use({ viewport: { width: 360, height: 780 } });

  for (const path of PAGES) {
    test(`${path} does not scroll sideways`, async ({ page }) => {
      await page.goto(path);
      await page.waitForLoadState("load");

      const { client, scroll } = await page.evaluate(() => ({
        client: document.documentElement.clientWidth,
        scroll: document.documentElement.scrollWidth,
      }));

      expect(scroll).toBeLessThanOrEqual(client);
    });
  }
});

test("the skip link moves focus to the main content", async ({ page }) => {
  await page.goto("/blocks");
  await page.keyboard.press("Tab");

  const skip = page.getByRole("link", { name: "Skip to content" });
  await expect(skip).toBeFocused();
  await skip.press("Enter");

  await expect(page.locator("main#main")).toBeFocused();
});

test("block and recipe pages have Markdown mirrors", async ({ request }) => {
  for (const path of ["/blocks/notifications", "/recipes/notification-bell"]) {
    const response = await request.get(`${path}.md`);

    expect(response.status()).toBe(200);
    expect(response.headers()["content-type"]).toContain("text/markdown");
    expect(await response.text()).toMatch(/^# /);
  }

  const negotiated = await request.get("/blocks/notifications", {
    headers: { Accept: "text/markdown" },
  });

  expect(negotiated.headers()["content-type"]).toContain("text/markdown");
  expect((await request.get("/blocks/unknown.md")).status()).toBe(404);
});
