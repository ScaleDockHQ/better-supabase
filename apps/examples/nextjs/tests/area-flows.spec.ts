import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import { signIn } from "./support/example-session";

// The ERP, manufacturing and quality and commerce stories of the seed
// (supabase/seeds/area-stories.sql): supplier bills that fall due, a grinder
// bill of materials with three production orders, two inspections with
// findings, and a collection of the coffee products. Every entry point is
// locked instant; the records and their sections stream in behind the frame.

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("the orders list shows its KPI band", async ({ page }) => {
  await page.goto("/shop/orders");

  await expect(page.getByRole("main").getByTestId("kpi-band")).toBeVisible();
  await expect(
    page.getByRole("main").getByText("Awaiting payment"),
  ).toBeVisible();
});

test("the payables list offers the pay due bills batch", async ({ page }) => {
  await page.goto("/finance/payables");

  await expect(
    page.getByRole("main").getByRole("button", { name: "Pay due bills" }),
  ).toBeVisible();
  await expect(page.getByText("Hooli hosting, November").first()).toBeVisible();
});

test("a production order opens with its operations and components", async ({
  page,
}) => {
  await page.goto("/manufacturing/orders");

  await expect(page.getByRole("main").getByTestId("kpi-band")).toBeVisible();

  const link = page.getByRole("link", { name: "MO-2026-0002" });

  await expect(link.first()).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.first().click();
      await page.waitForURL((url) =>
        url.pathname.startsWith("/manufacturing/orders/"),
      );
    },
    visible: [page.getByRole("link", { name: "All production orders" })],
  });

  const main = page.getByRole("main");

  await expect(main.getByText("Assemble and calibrate")).toBeVisible();
  await expect(main.getByText("Components", { exact: true })).toBeVisible();
});

test("an inspection opens with its findings and cases", async ({ page }) => {
  await page.goto("/inspections/register");

  const link = page.getByRole("link", { name: "AUD-2026-002" });

  await expect(link.first()).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.first().click();
      await page.waitForURL((url) => url.pathname.startsWith("/inspections/"));
    },
    visible: [page.getByRole("link", { name: "All inspections" })],
  });

  const main = page.getByRole("main");

  await expect(
    main.getByText("Calibration records missing for the torque tool"),
  ).toBeVisible();
  await expect(main.getByText("Findings need a case")).toBeVisible();
});

test("a product opens with its price and record sections", async ({ page }) => {
  await page.goto("/shop");

  const link = page.getByRole("link", { name: "Espresso beans, 1 kg" });

  await expect(link.first()).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.first().click();
      await page.waitForURL((url) =>
        url.pathname.startsWith("/shop/products/"),
      );
    },
    visible: [page.getByRole("link", { name: "All products" })],
  });

  await expect(
    page.getByRole("main").getByText("BEANS-1KG").first(),
  ).toBeVisible();
});
