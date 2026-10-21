import { expect, test, type Locator, type Page } from "@playwright/test";

import { field } from "./nav";
import { users } from "./users";

const rowOf = (page: Page, title: string): Locator =>
  page
    .getByRole("row")
    .filter({ has: page.getByRole("link", { name: title, exact: true }) });

test.describe("owner", () => {
  test.use({ storageState: users.admin.storageState });

  // The edit keeps the row count, so the grid repaints only when it
  // publishes on new data, not on `recordCount`.
  test("a task edited in place shows its new status in the grid", async ({
    page,
  }) => {
    const project = `AAA grid ${String(Date.now())}`;
    const title = `${project} task`;

    await page.goto("/en/projects");
    await page.getByRole("button", { name: "New project" }).first().click();
    await field(page, "Name").fill(project);
    await page.getByRole("button", { name: "Create project" }).click();

    await page.getByRole("button", { name: "New task" }).first().click();
    await field(page, "Title").fill(title);
    await field(page, "Project").click();
    await page.getByRole("option", { name: project }).click();
    await page.getByRole("button", { name: "Create task" }).click();
    await expect(rowOf(page, title)).toContainText("To do");

    const rows = await page
      .getByRole("checkbox", { name: "Select row" })
      .count();

    await rowOf(page, title)
      .getByRole("checkbox", { name: "Select row" })
      .click();
    await page.getByRole("button", { name: "Mark Doing" }).click();

    await expect(rowOf(page, title)).toContainText("Doing");
    await expect(
      page.getByRole("checkbox", { name: "Select row" }),
    ).toHaveCount(rows);
  });
});
