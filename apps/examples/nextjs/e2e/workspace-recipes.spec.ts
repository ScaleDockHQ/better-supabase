import { expect, test } from "@playwright/test";

import { heading, visibleTestId, visibleText } from "./nav";
import { users } from "./users";

test.describe("push opt-in", () => {
  test.use({ storageState: users.member.storageState });

  test("asks for a VAPID key when push isn't configured", async ({ page }) => {
    await page.goto("/en/settings/preferences");

    const card = visibleTestId(page, "push-opt-in");

    await expect(card).toBeVisible();
    await expect(card.getByText("Push isn't set up yet")).toBeVisible();
    await expect(
      card.getByRole("link", { name: "Read the push guide" }),
    ).toBeVisible();
  });
});

test.describe("metrics dashboard", () => {
  test.use({ storageState: users.admin.storageState });

  test("shows the customers metric or its empty state", async ({ page }) => {
    await page.goto("/en/metrics");

    await expect(heading(page, "Metrics")).toBeVisible();
    await expect(
      visibleTestId(page, "metrics-dashboard").or(
        visibleText(page, "No data in the last 30 days"),
      ),
    ).toBeVisible();
  });
});

// The `beta-page` flag is on for Acme only.
for (const [name, value] of [
  ["admin", "On"],
  ["globex", "Off"],
] as const) {
  test.describe(`feature flags for ${name}`, () => {
    test.use({ storageState: users[name].storageState });

    test(`beta-page reads ${value}`, async ({ page }) => {
      await page.goto("/en/settings/organization");
      await expect(visibleTestId(page, "feature-flag-beta-page")).toContainText(
        value,
      );
    });
  });
}
