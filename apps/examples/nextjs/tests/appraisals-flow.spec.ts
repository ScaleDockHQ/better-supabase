/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import { expect, test } from "@playwright/test";

import { signIn } from "./support/example-session";

// The seed opens a Mid-year review with a Delivery and Teamwork rubric. Ada
// writes the only review of her own appraisal, which moves it to reviewed, and
// then calibrates it.

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("a self review moves the appraisal to reviewed and a calibration keeps its reason", async ({
  page,
}) => {
  await page.goto("/appraisals");
  await page.getByRole("main").getByRole("link", { name: "Ada Admin" }).click();
  await page.waitForURL((url) => url.pathname.startsWith("/appraisals/"));

  const main = page.getByRole("main");

  await main.getByRole("button", { name: "Write review" }).click();

  const review = page.getByRole("dialog");

  await review.getByLabel("Delivery").fill("4");
  await review.getByLabel("Teamwork").fill("5");
  await review.getByLabel("Comments").fill("Shipped the billing rework.");
  await review.getByRole("button", { name: "Submit review" }).click();

  await expect(page.getByText("Review submitted")).toBeVisible();
  await expect(
    main.getByText("Reviewed", { exact: true }).filter({ visible: true }),
  ).toBeVisible();

  await main.getByRole("button", { name: "Calibrate" }).click();

  const calibrate = page.getByRole("dialog");

  await calibrate.getByLabel("Rating").fill("3");
  await calibrate
    .getByLabel("Reason")
    .fill("Aligned with the team in the session.");
  await calibrate.getByRole("button", { name: "Calibrate" }).click();

  await expect(page.getByText("Appraisal calibrated")).toBeVisible();
  await expect(
    main.getByText("Calibrated", { exact: true }).filter({ visible: true }),
  ).toBeVisible();
  await expect(
    main.getByText("Aligned with the team in the session."),
  ).toBeVisible();
});
