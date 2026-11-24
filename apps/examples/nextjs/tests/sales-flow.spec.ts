/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import { signIn } from "./support/example-session";

// The sales story of the seed: the Sales pipeline with six deals, three
// contracts and two companies. Every entry point of the area is locked
// instant, and the figures and sections stream in behind the frame.

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("the sales hub shows its KPI band and opens the deals from it", async ({
  page,
}) => {
  await page.goto("/crm");

  await expect(page.getByRole("main").getByTestId("kpi-band")).toBeVisible();
  await expect(page.getByText("Closing soonest")).toBeVisible();

  const link = page.getByRole("link", { name: /Open deals/ });

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) => url.pathname === "/crm/deals");
    },
    visible: [page.getByRole("heading", { name: "Deals" })],
  });
});

// A same-route search param change does not complete under the instant lock
// (finding 2 in tmp/findings/sample-depth-findings.md), so the view switch is
// checked on the result: the URL, the active link and the view's content.
// oxlint-disable-next-line vitest/prefer-each -- Playwright has no `test.each` (1 finding).
for (const [view, content] of [
  ["Board", "Negotiation"],
  ["Calendar", "Annual plan for Globex"],
  ["Timeline", "Annual plan for Globex"],
] as const) {
  test(`the deals ${view.toLowerCase()} view shows the seeded deals`, async ({
    page,
  }) => {
    await page.goto("/crm/deals");
    await page
      .getByRole("navigation", { name: "Views" })
      .getByRole("link", { name: view })
      .click();
    await page.waitForURL(
      (url) => url.searchParams.get("view") === view.toLowerCase(),
    );

    await expect(page.getByText(content).first()).toBeVisible();
  });
}

test("a deal opens with its stage path, then its sections stream in", async ({
  page,
}) => {
  await page.goto("/crm/deals");

  const link = page.getByRole("link", { name: /^DEAL-\d+$/ });

  await expect(link.first()).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.first().click();
      await page.waitForURL((url) => url.pathname.startsWith("/crm/deals/"));
    },
    visible: [page.getByRole("link", { name: "All deals" })],
  });

  await expect(page.getByRole("list", { name: "Deal stage" })).toBeVisible();
});

test("a contract opens with its status path and its record sections", async ({
  page,
}) => {
  await page.goto("/crm/contracts");

  const link = page.getByRole("link", { name: "Globex master services" });

  await expect(link.first()).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.first().click();
      await page.waitForURL((url) =>
        url.pathname.startsWith("/crm/contracts/"),
      );
    },
    visible: [page.getByRole("link", { name: "All contracts" })],
  });

  await expect(
    page.getByRole("list", { name: "Contract status" }),
  ).toBeVisible();
  await expect(page.getByText("Obligations", { exact: true })).toBeVisible();
});

test("an area hub opens instantly from the areas page and shows its figures", async ({
  page,
}) => {
  await page.goto("/areas");

  const link = page.getByRole("link", { name: "ERP", exact: true });

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) => url.pathname === "/areas/erp");
    },
    visible: [page.getByRole("link", { name: "All areas" })],
  });

  await expect(page.getByRole("main").getByTestId("kpi-band")).toBeVisible();
});
