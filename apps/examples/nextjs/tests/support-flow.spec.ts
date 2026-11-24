/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import { signIn } from "./support/example-session";

// The support story: the two nonconformity cases the lab seed opens
// (`supabase/seeds/example.sql`), listed on the table view of /cases and opened
// on their own page. Every entry point is locked instant; the figures, rows and
// sections stream in behind the frame.

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("the case table shows its KPI band and the seeded cases", async ({
  page,
}) => {
  await page.goto("/cases");
  await page
    .getByRole("navigation", { name: "Views" })
    .getByRole("link", { name: "Table" })
    .click();
  await page.waitForURL((url) => url.searchParams.get("view") === "table");

  const main = page.getByRole("main");

  await expect(main.getByTestId("kpi-band")).toBeVisible();
  await expect(
    main.getByRole("link", { name: "SMP-4: Moisture out of specification" }),
  ).toBeVisible();
});

test("a case opens on its own page, then its discussion streams in", async ({
  page,
}) => {
  await page.goto("/cases?view=table");

  const link = page
    .getByRole("main")
    .getByRole("link", { name: "SMP-4: Moisture out of specification" });

  await expect(link).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) => url.pathname.startsWith("/cases/"));
    },
    visible: [page.getByRole("link", { name: "All cases" })],
  });

  await expect(
    page.getByRole("main").getByRole("button", { name: "Discuss" }),
  ).toBeVisible();
});

test("discussing a case posts the comment", async ({ page }) => {
  await page.goto("/cases?view=table");

  const main = page.getByRole("main");

  await main
    .getByRole("link", { name: "SMP-4: Moisture out of specification" })
    .click();
  await page.waitForURL((url) => url.pathname.startsWith("/cases/"));
  await main.getByRole("button", { name: "Discuss" }).click();

  const dialog = page.getByRole("dialog");

  await dialog.getByLabel("Comment").fill("Re-test scheduled for Monday.");
  await dialog.getByRole("button", { name: "Post comment" }).click();

  await expect(main.getByText("Re-test scheduled for Monday.")).toBeVisible();
});

test("opening a ticket reports it with its response clocks", async ({
  page,
}) => {
  await page.goto("/cases");

  const main = page.getByRole("main");

  await main.getByRole("button", { name: "Open ticket" }).click();

  const dialog = page.getByRole("dialog");

  await dialog.getByLabel("Title").fill("Loading dock light is out");
  await dialog.getByRole("button", { name: "Open ticket" }).click();

  await expect(page.getByText("Ticket opened")).toBeVisible();
});
