import { AxeBuilder } from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const RECIPE = "/recipes/notification-bell";

const WCAG = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

test("the platform tabs keep the choice in ?platform=", async ({ page }) => {
  await page.goto(RECIPE);

  const web = page.getByRole("tab", { name: "Web", exact: true });
  const native = page.getByRole("tab", { name: "Native", exact: true });
  const prompt = page.getByTestId("recipe-prompt-text");

  await expect(web).toHaveAttribute("aria-selected", "true");
  await expect(prompt).toContainText("React web app");

  await native.click();
  await expect(native).toHaveAttribute("aria-selected", "true");
  await expect(page).toHaveURL(/[?&]platform=native\b/);
  await expect(prompt).toContainText("React Native");
  await expect(page.getByRole("tabpanel")).toContainText("react-native");

  await web.click();
  await expect(web).toHaveAttribute("aria-selected", "true");
  await expect(page).not.toHaveURL(/platform=/);
});

test("a link with ?platform=native opens the Native tab", async ({ page }) => {
  await page.goto(`${RECIPE}?platform=native`);

  await expect(
    page.getByRole("tab", { name: "Native", exact: true }),
  ).toHaveAttribute("aria-selected", "true");
  await expect(page.getByTestId("recipe-prompt-text")).toContainText(
    "React Native",
  );
});

test("the copy button puts the prompt on the clipboard", async ({
  page,
  context,
}) => {
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await page.goto(`${RECIPE}?platform=native`);
  await expect(
    page.getByRole("tab", { name: "Native", exact: true }),
  ).toHaveAttribute("aria-selected", "true");

  const prompt = await page.getByTestId("recipe-prompt-text").textContent();

  await page.getByRole("button", { name: "Copy the prompt" }).click();
  await expect(
    page.getByTestId("recipe-prompt").getByText("Copied", { exact: true }),
  ).toBeAttached();

  const copied = await page.evaluate(() => navigator.clipboard.readText());

  expect(copied.trim()).toBe(prompt?.trim());
  expect(copied).toContain("npx better-supabase add notifications");
  expect(copied).toContain("/recipes/notification-bell.md");
});

for (const colorScheme of ["light", "dark"] as const) {
  test.describe(`${colorScheme} theme`, () => {
    test.use({ colorScheme });

    for (const path of ["/recipes", RECIPE, `${RECIPE}?platform=native`]) {
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
