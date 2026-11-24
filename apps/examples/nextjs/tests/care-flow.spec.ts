/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import { signIn } from "./support/example-session";

// The care story of the seed: two clients, a published plan for Noor Haddad, a
// draft prescription and consent for Noor only. Every entry point is locked
// instant; the counts and sections stream in behind the frame.

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("the care plan list opens a plan with its dossier link", async ({
  page,
}) => {
  await page.goto("/care-plans");

  const main = page.getByRole("main");

  await expect(
    main.getByTestId("kpi-band").filter({ visible: true }),
  ).toBeVisible();

  const link = main.getByRole("link", { name: "Mobility and pain plan" });

  await expect(link).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) => url.pathname.startsWith("/care-plans/"));
    },
    visible: [page.getByRole("link", { name: "All care plans" })],
  });

  await expect(page.getByRole("link", { name: "Open dossier" })).toBeVisible();
  await expect(
    page
      .getByRole("main")
      .getByRole("heading", { name: "Mobility and pain plan" }),
  ).toBeVisible();
});

test("the prescription list opens the draft with its status", async ({
  page,
}) => {
  await page.goto("/prescriptions");

  const main = page.getByRole("main");

  await expect(
    main.getByTestId("kpi-band").filter({ visible: true }),
  ).toBeVisible();

  const link = main
    .getByRole("link")
    .filter({ hasText: /Paracetamol|Draft prescription/ })
    .first();

  await expect(link).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) =>
        url.pathname.startsWith("/prescriptions/"),
      );
    },
    visible: [page.getByRole("link", { name: "All prescriptions" })],
  });

  await expect(page.getByRole("main").getByText("Draft").first()).toBeVisible();
});

test("the dossier shows its counts and refuses a prescription without consent", async ({
  page,
}) => {
  await page.goto("/care");
  await page
    .getByRole("main")
    .getByRole("link", { name: "Jan de Vries" })
    .click();
  await page.waitForURL((url) => url.pathname.startsWith("/care/"));

  await expect(
    page.getByRole("main").getByTestId("kpi-band").filter({ visible: true }),
  ).toBeVisible();

  await page.getByRole("tab", { name: "Medication" }).click();
  await page.getByRole("button", { name: "Prescribe" }).first().click();
  await page.getByRole("combobox", { name: "Medication" }).click();
  await page.getByRole("option", { name: /Paracetamol/ }).click();
  await page.getByLabel("Dose").fill("500");
  await page.getByRole("button", { name: "Prescribe" }).last().click();

  await expect(
    page.getByRole("alert").or(page.getByRole("status")).first(),
  ).toBeVisible();
});
