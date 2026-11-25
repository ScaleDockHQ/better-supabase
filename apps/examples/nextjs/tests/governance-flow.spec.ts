import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import { signIn } from "./support/example-session";

// The governance story of the seed: a rated supplier risk and two tracked
// vulnerabilities, one critical. Every entry point is locked instant; the
// figures and sections stream in behind the frame.

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("a risk opens with its rating, tabs and record sections", async ({
  page,
}) => {
  await page.goto("/risks");

  const link = page
    .getByRole("main")
    .getByRole("link", { name: "Payment provider outage" });

  await expect(link).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) => url.pathname.startsWith("/risks/"));
    },
    visible: [page.getByRole("link", { name: "All risks" })],
  });

  const main = page.getByRole("main");

  await expect(
    main.getByRole("heading", { name: "Payment provider outage" }),
  ).toBeVisible();
  await expect(main.getByRole("link", { name: "Activity" })).toBeVisible();
  await expect(
    main.getByRole("button", { name: "Export record" }),
  ).toBeVisible();
});

test("a risk can be exported with its audit entry", async ({ page }) => {
  await page.goto("/risks");
  await page
    .getByRole("main")
    .getByRole("link", { name: "Payment provider outage" })
    .click();
  await page.getByRole("button", { name: "Export record" }).click();

  await expect(page.getByText("Export requested").first()).toBeVisible();
});

test("the vulnerability list shows its KPI band and opens a record", async ({
  page,
}) => {
  await page.goto("/advisories/vulnerabilities");

  const main = page.getByRole("main");

  await expect(
    main.getByTestId("kpi-band").filter({ visible: true }),
  ).toBeVisible();

  const link = main.getByRole("link", { name: "CVE-2026-31001" });

  await expect(link).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) =>
        url.pathname.startsWith("/advisories/vulnerabilities/"),
      );
    },
    visible: [page.getByRole("link", { name: "All vulnerabilities" })],
  });

  await expect(
    page.getByRole("main").getByRole("heading", { name: "CVE-2026-31001" }),
  ).toBeVisible();
});

test("a failing control passes once evidence answers its task", async ({
  page,
}) => {
  await page.goto("/compliance");
  await page
    .getByRole("main")
    .getByRole("link", { name: "ISO/IEC 27001" })
    .click();

  const control = page
    .getByRole("main")
    .getByRole("link", { name: "Information backup" });

  await expectInstant(page, {
    during: async () => {
      await control.click();
      await page.waitForURL((url) =>
        url.pathname.startsWith("/compliance/controls/"),
      );
    },
    visible: [page.getByRole("link", { name: "All frameworks" })],
  });

  const main = page.getByRole("main");

  await expect(
    main.getByText("Failing", { exact: true }).filter({ visible: true }),
  ).toBeVisible();
  await expect(main.getByText("Expired", { exact: true })).toBeVisible();

  await main
    .getByRole("row", { name: /Monthly restore test/ })
    .getByRole("button", { name: "Collect" })
    .click();

  const dialog = page.getByRole("dialog");

  await dialog
    .getByLabel("Note")
    .fill("Restore of the November backup took 12 minutes.");
  await dialog.getByRole("button", { name: "Add evidence" }).click();

  await expect(page.getByText("Evidence added")).toBeVisible();
  await expect(
    main.getByText("Passing", { exact: true }).filter({ visible: true }),
  ).toBeVisible();
  await expect(
    main.getByText("Restore of the November backup took 12 minutes."),
  ).toBeVisible();
});
