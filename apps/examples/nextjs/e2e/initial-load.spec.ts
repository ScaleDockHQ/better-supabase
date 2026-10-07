import { instant } from "@next/playwright";
import { expect, test } from "@playwright/test";

import { heading, visibleTestId } from "./nav";
import { baseURL } from "./server";
import { users } from "./users";

for (const locale of ["en", "nl"] as const) {
  test.describe(`initial load in ${locale}`, () => {
    test.describe("signed in", () => {
      test.use({ storageState: users.admin.storageState });

      test("the dashboard serves its static shell", async ({ page }) => {
        await instant(
          page,
          async () => {
            await page.goto(`/${locale}`);
            await expect(heading(page, "Dashboard")).toBeVisible();
            await expect(
              page.getByRole("navigation", { name: /^(Main|Hoofdmenu)$/ }),
            ).toHaveAttribute("aria-busy", "true");
            // The summary and the switcher read the session, so they are never in the static shell.
            await expect(page.getByTestId("workspace-summary")).toHaveCount(0);
            await expect(visibleTestId(page, "organization-name")).toHaveCount(
              0,
            );
          },
          { baseURL },
        );
        await expect(page.getByTestId("workspace-summary")).toBeVisible();
        await expect(visibleTestId(page, "organization-name")).toHaveText(
          "Acme",
        );
      });

      test("a customer page serves its static shell", async ({ page }) => {
        await page.goto(`/${locale}/customers`);
        const href = await page
          .getByRole("link", { name: "Road Runner Inc" })
          .getAttribute("href");
        await instant(
          page,
          async () => {
            await page.goto(href ?? "");
            await expect(
              page.getByRole("link", {
                name: locale === "en" ? "All customers" : "Alle klanten",
              }),
            ).toBeVisible();
            await expect(heading(page, "Road Runner Inc")).toHaveCount(0);
          },
          { baseURL },
        );
        await expect(heading(page, "Road Runner Inc")).toBeVisible();
      });
    });

    for (const [path, title] of [
      ["/login", { en: "Welcome back", nl: "Welkom terug" }],
      ["/signup", { en: "Create your account", nl: "Maak je account" }],
      [
        "/forgot-password",
        { en: "Reset your password", nl: "Wachtwoord opnieuw instellen" },
      ],
    ] as const)
      test(`${path} is fully static`, async ({ page }) => {
        await instant(
          page,
          async () => {
            await page.goto(`/${locale}${path}`);
            await expect(
              page.getByText(title[locale], { exact: true }),
            ).toBeVisible();
          },
          { baseURL },
        );
      });
  });
}
