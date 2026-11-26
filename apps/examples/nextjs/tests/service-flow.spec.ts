import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import { signIn } from "./support/example-session";

// The service story of the seed (`supabase/seeds/example.sql`): a forklift
// service on site, a dock door check in the day plan and three parcels at the
// stages of tracking. Every entry point is locked instant; the figures, rows and
// sections stream in behind the frame.

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("the work order table shows its KPI band and the seeded visits", async ({
  page,
}) => {
  await page.goto("/field/dispatch");
  await page
    .getByRole("navigation", { name: "Views" })
    .getByRole("link", { name: "Table" })
    .click();
  await page.waitForURL((url) => url.searchParams.get("view") === "table");

  const main = page.getByRole("main");

  await expect(
    main.getByTestId("kpi-band").filter({ visible: true }),
  ).toBeVisible();
  await expect(
    main.getByRole("link", { name: "Forklift hydraulic service" }),
  ).toBeVisible();
  await expect(
    main.getByRole("link", { name: "Dock door sensor check" }),
  ).toBeVisible();
});

test("a work order opens with its visit path, then its sections stream in", async ({
  page,
}) => {
  await page.goto("/field/dispatch?view=table");

  const link = page
    .getByRole("main")
    .getByRole("link", { name: "Dock door sensor check" });

  await expect(link).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) =>
        url.pathname.startsWith("/field/dispatch/"),
      );
    },
    visible: [page.getByRole("link", { name: "All work orders" })],
  });

  const main = page.getByRole("main");

  await expect(main.getByRole("list", { name: "Visit status" })).toBeVisible();
  await expect(
    main.getByText("Parts used").filter({ visible: true }),
  ).toBeVisible();
});

test("the shipment table opens a parcel with its tracking timeline", async ({
  page,
}) => {
  await page.goto("/field/shipments?view=table");

  const main = page.getByRole("main");

  await expect(
    main.getByTestId("kpi-band").filter({ visible: true }),
  ).toBeVisible();

  const link = main.getByRole("link", { name: "SH-SEED-02" });

  await expect(link).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) =>
        url.pathname.startsWith("/field/shipments/"),
      );
    },
    visible: [page.getByRole("link", { name: "All shipments" })],
  });

  await expect(
    main.getByText("Picked up by the carrier").filter({ visible: true }),
  ).toBeVisible();
});

// Keep this test last: it completes the seeded visit, so a second run finds the
// work order done and checks that instead.
test("completing the visit records the part and marks the work order done", async ({
  page,
}) => {
  await page.goto("/field/dispatch?view=table");

  const main = page.getByRole("main");

  await main.getByRole("link", { name: "Forklift hydraulic service" }).click();
  await page.waitForURL((url) => url.pathname.startsWith("/field/dispatch/"));

  const open = main.getByRole("button", { name: "Complete visit" });

  if (await open.isVisible()) {
    await open.click();

    const dialog = page.getByRole("dialog");

    await dialog.getByLabel("Part used").fill("Hydraulic filter");
    await dialog.getByLabel("Quantity").fill("1");
    await dialog.getByLabel("Note").fill("Filter replaced, no leaks.");
    await dialog.getByRole("button", { name: "Complete visit" }).click();
  }

  await expect(main.getByText("Done").first()).toBeVisible();
  await expect(
    main.getByText("Hydraulic filter").filter({ visible: true }),
  ).toBeVisible();
});
