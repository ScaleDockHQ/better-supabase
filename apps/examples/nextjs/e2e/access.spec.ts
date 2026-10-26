import { expect, test } from "@playwright/test";

import { cardTitle, signIn, visibleTestId } from "./nav";
import { accessToken } from "./tokens";
import { users } from "./users";

/**
 * The teams and permissions blocks end to end: an owner manages a team, and a
 * permission override on a catalog role changes what a member can do on the
 * next page load.
 */

const ACME = "00000000-0000-4000-8000-000000000001";
const ROAD_RUNNER = "00000000-0000-4000-8000-00000000a001";

test.describe("owner", () => {
  test.use({ storageState: users.admin.storageState });

  test("creates a team, adds and removes a member, and deletes it", async ({
    page,
  }) => {
    const name = `QA ${Date.now()}`;

    await page.goto("/en/settings/teams");
    await expect(cardTitle(page, "Teams")).toBeVisible();

    await page.getByRole("button", { name: "New team" }).click();
    const dialog = page.getByRole("dialog", { name: "New team" });
    await dialog.getByLabel("Name").fill(name);
    await dialog.getByRole("button", { name: "Create" }).click();
    await expect(dialog).toBeHidden();

    await page.getByRole("link", { name, exact: true }).click();
    await page.waitForURL((url) =>
      url.pathname.startsWith("/en/settings/teams/"),
    );
    const members = page.getByTestId("team-members");
    await expect(members.getByText("Nobody is on this team")).toBeVisible();

    await members.getByRole("combobox", { name: "Member to add" }).click();
    await page.getByRole("option", { name: "Max Member" }).click();
    await members.getByRole("button", { name: "Add" }).click();

    const remove = members.getByRole("button", {
      name: "Take Max Member off the team",
    });

    await expect(remove).toBeVisible();

    // The change is in the database, not only in the optimistic state.
    await page.reload();
    await expect(remove).toBeVisible();

    await remove.click();
    await expect(members.getByText("Nobody is on this team")).toBeVisible();

    await page.getByRole("button", { name: "Delete" }).click();
    await page
      .getByRole("alertdialog")
      .getByRole("button", { name: "Delete" })
      .click();
    await page.waitForURL((url) => url.pathname === "/en/settings/teams");
    await expect(page.getByRole("link", { name, exact: true })).toHaveCount(0);
  });
});

test.describe("role overrides", () => {
  // Restores the member role's default even when an assertion failed midway.
  test.afterEach(async ({ request }) => {
    const response = await request.post(
      `/api/v1/organizations/${ACME}/role-overrides`,
      {
        headers: { authorization: `Bearer ${await accessToken("admin")}` },
        data: {
          roleId: "member",
          permission: "customers.write",
          granted: null,
        },
      },
    );

    expect(response.ok()).toBe(true);
  });

  test("granting customers.write to member lets members edit customers", async ({
    browser,
  }) => {
    const member = await browser.newPage();
    await signIn(member, users.member.email);
    await member.goto(`/en/customers/${ROAD_RUNNER}`);
    const ownerTeam = visibleTestId(member, "owner-team");
    await expect(ownerTeam).toBeDisabled();

    const admin = await browser.newPage({
      storageState: users.admin.storageState,
    });

    await admin.goto("/en/settings/roles");
    await visibleTestId(admin, "roles")
      .getByRole("link", { name: "Member" })
      .click();
    await admin.waitForURL((url) =>
      url.pathname.startsWith("/en/settings/roles/"),
    );

    const matrix = visibleTestId(admin, "permission-matrix");
    await matrix.getByLabel("Search permissions").fill("customers.write");
    const toggle = matrix.getByRole("switch", { name: "customers.write" });
    await expect(toggle).not.toBeChecked();
    await toggle.click();
    await expect(matrix.getByText("Granted here")).toBeVisible();

    await member.reload();
    await expect(ownerTeam).toBeEnabled();

    await matrix
      .getByRole("button", { name: "Reset customers.write to the default" })
      .click();
    await expect(matrix.getByText("Granted here")).toHaveCount(0);
    await expect(toggle).not.toBeChecked();

    await member.reload();
    await expect(ownerTeam).toBeDisabled();

    await admin.close();
    await member.close();
  });
});
