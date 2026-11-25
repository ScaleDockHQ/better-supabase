/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import { signIn } from "./support/example-session";

// The projects story of the seed (`supabase/seeds/example.sql`): two projects with
// a budget and tracked time on the first. The portfolio and the project page read
// the `projects` composite behind their own Suspense; both entry points are locked
// instant.

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("the portfolio opens instantly, then shows the figures and the projects", async ({
  page,
}) => {
  await page.goto("/projects");

  const link = page.getByRole("main").getByRole("link", { name: "Portfolio" });

  await expect(link).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) =>
        url.pathname.endsWith("/projects/portfolio"),
      );
    },
    visible: [page.getByRole("heading", { name: "Portfolio" })],
  });

  const main = page.getByRole("main");

  await expect(
    main.getByTestId("kpi-band").filter({ visible: true }),
  ).toBeVisible();
  await expect(
    main.getByRole("link", { name: "Warehouse automation rollout" }),
  ).toBeVisible();
  await expect(
    main.getByText("12 h tracked, 10 h billable").filter({ visible: true }),
  ).toBeVisible();
});

test("a project shows its tracked time against the budget", async ({
  page,
}) => {
  await page.goto("/projects/portfolio");

  const link = page
    .getByRole("main")
    .getByRole("link", { name: "Warehouse automation rollout" });

  await expect(link).toBeVisible();
  await link.hover();
  await page.waitForLoadState("networkidle");

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) => /\/projects\/[^/]+$/.test(url.pathname));
    },
    visible: [page.getByRole("link", { name: "All projects" })],
  });

  const main = page.getByRole("main");

  await expect(
    main.getByText("Time and budget").filter({ visible: true }),
  ).toBeVisible();
  await expect(
    main.getByText("Budget left").filter({ visible: true }),
  ).toBeVisible();
});

test("an admin approves a member's submitted week and invoices it", async ({
  page,
}) => {
  // The seed submits one week for the member; submitting opens an approval
  // request, so the composite decides that request instead of approving the
  // week directly.
  await page.goto("/projects/portfolio");

  const card = page
    .getByRole("main")
    .locator("[data-slot=card]")
    .filter({ hasText: "Time awaiting approval" });

  const button = card.getByRole("button", { name: "Approve and invoice" });

  await expect(button).toBeVisible();
  await button.click();

  await expect(page.getByText("Week approved and invoiced")).toBeVisible();
  await expect(
    card.getByText("No submitted week is waiting for approval."),
  ).toBeVisible();
});
