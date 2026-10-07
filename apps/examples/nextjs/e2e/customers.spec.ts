import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import { clickSidebar, field, heading, sidebarLink, visibleText } from "./nav";
import { users } from "./users";

test.describe("owner", () => {
  test.use({ storageState: users.admin.storageState });

  test("customers come from the per-session App Shell on a click", async ({
    page,
  }) => {
    await page.goto("/en");
    await expect(sidebarLink(page, "Customers")).toBeVisible();
    await expectInstant(page, {
      during: clickSidebar(page, "Customers", "/en/customers"),
      visible: [
        heading(page, "Customers"),
        page.getByRole("link", { name: "Road Runner Inc" }),
        page.getByTestId("status-facets"),
      ],
      maxCalls: 8,
      maxWaves: 2,
    });
  });

  test("a customer's detail comes from the App Shell on a click", async ({
    page,
  }) => {
    await page.goto("/en/customers");
    await expectInstant(page, {
      during: async () => {
        await page.getByRole("link", { name: "Road Runner Inc" }).click();
        await page.waitForURL((url) =>
          url.pathname.startsWith("/en/customers/"),
        );
      },
      visible: [
        heading(page, "Road Runner Inc"),
        visibleText(page, "Recent notes"),
      ],
    });
  });

  test("a new customer shows on the next visit", async ({ page }) => {
    const name = `AAA e2e ${String(Date.now())}`;
    await page.goto("/en/customers");
    await page.getByRole("button", { name: "Add customer" }).click();
    await field(page, "Name").fill(name);
    await page.getByRole("button", { name: "Add", exact: true }).click();
    await expect(page.getByRole("link", { name })).toBeVisible();

    await clickSidebar(page, "Dashboard", "/en")();
    await clickSidebar(page, "Customers", "/en/customers")();
    await expect(page.getByRole("link", { name })).toBeVisible();

    await page.reload();
    await expect(page.getByRole("link", { name })).toBeVisible();
  });
});

test.describe("member", () => {
  test.use({ storageState: users.member.storageState });

  test("customers come from the App Shell, without write access", async ({
    page,
  }) => {
    await page.goto("/en");
    await expectInstant(page, {
      during: clickSidebar(page, "Customers", "/en/customers"),
      visible: [
        heading(page, "Customers"),
        page.getByRole("link", { name: "Road Runner Inc" }),
        page.getByText("Only admins can add customers."),
      ],
    });
    await expect(
      page.getByRole("button", { name: "Add customer" }),
    ).toHaveCount(0);
  });
});

test.describe("Globex", () => {
  test.use({ storageState: users.globex.storageState });

  test("sees only its own customers", async ({ page }) => {
    await page.goto("/en/customers");
    await expect(page.getByRole("link", { name: "Initech" })).toBeVisible();
    await expect(
      page.getByRole("link", { name: "Road Runner Inc" }),
    ).toHaveCount(0);
  });
});
