import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import { signIn } from "./support/example-session";

// The people story of the seed (`supabase/seeds/example.sql`): two open jobs
// with four applications, the onboarding program of the new hires and a
// published course with two learners. Every entry point is locked instant; the
// figures, rows and sections stream in behind the frame.

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("the application table shows its KPI band and the seeded openings", async ({
  page,
}) => {
  await page.goto("/people/hiring");
  await page
    .getByRole("navigation", { name: "Views" })
    .getByRole("link", { name: "Table" })
    .click();
  await page.waitForURL((url) => url.searchParams.get("view") === "table");

  const main = page.getByRole("main");

  await expect(
    main.getByTestId("kpi-band").filter({ visible: true }),
  ).toBeVisible();
  await expect(main.getByText("Support agent").first()).toBeVisible();
  await expect(main.getByText("Account executive").first()).toBeVisible();
});

test("an application opens with its stage path, then its sections stream in", async ({
  page,
}) => {
  await page.goto("/people/hiring?view=table");

  const main = page.getByRole("main");
  const link = main.locator('a[href*="/people/hiring/"]').first();

  await expect(link).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) =>
        /\/people\/hiring\/[^/]+$/u.test(url.pathname),
      );
    },
    visible: [page.getByRole("link", { name: "All applications" })],
  });

  await expect(
    main
      .filter({ visible: true })
      .getByRole("list", { name: "Application stage" }),
  ).toBeVisible();
  await expect(
    main.getByText("Interviews", { exact: true }).filter({ visible: true }),
  ).toBeVisible();
});

test("the people board groups the employees by status", async ({ page }) => {
  await page.goto("/people?view=board");

  const main = page.getByRole("main");

  await expect(
    main.getByTestId("kpi-band").filter({ visible: true }),
  ).toBeVisible();
  await expect(main.getByText("Active").first()).toBeVisible();
  await expect(main.getByRole("link", { name: "Max Member" })).toBeVisible();
});

test("an employee opens with its tabs, then the onboarding checklist and leave balance", async ({
  page,
}) => {
  await page.goto("/people");

  const link = page.getByRole("main").getByRole("link", { name: "Max Member" });

  await expect(link).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) => /\/people\/[^/]+$/u.test(url.pathname));
    },
    visible: [page.getByRole("link", { name: "All people" })],
  });

  const main = page.getByRole("main");

  await expect(
    main.getByText("Leave balance", { exact: true }).filter({ visible: true }),
  ).toBeVisible();

  await main.getByRole("link", { name: "Onboarding" }).click();
  await page.waitForURL((url) => url.searchParams.get("tab") === "onboarding");
  await expect(main.getByRole("link", { name: "Onboarding" })).toHaveAttribute(
    "aria-current",
    "page",
  );
});

test("the course lists its enrollments with the assign action", async ({
  page,
}) => {
  await page.goto("/courses?view=table");

  const main = page.getByRole("main");

  await expect(
    main.getByTestId("kpi-band").filter({ visible: true }),
  ).toBeVisible();

  const link = main.getByRole("link", { name: "Security basics" });

  await expect(link).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) => url.pathname.startsWith("/courses/"));
    },
    visible: [page.getByRole("link", { name: "All courses" })],
  });

  await main.getByRole("link", { name: "Enrollments" }).click();
  await page.waitForURL((url) => url.searchParams.get("tab") === "enrollments");

  await expect(
    main.getByText("Who takes this course").filter({ visible: true }),
  ).toBeVisible();
  await expect(
    main.getByText("Max Member").filter({ visible: true }),
  ).toBeVisible();
});

test("the shift and leave overviews show their KPI band", async ({ page }) => {
  await page.goto("/shifts?view=table");
  await expect(
    page.getByRole("main").getByTestId("kpi-band").filter({ visible: true }),
  ).toBeVisible();

  await page.goto("/people/leave");
  await expect(
    page.getByRole("main").getByTestId("kpi-band").filter({ visible: true }),
  ).toBeVisible();
});

// Keep this test last: it hires the first open application, so a second run
// finds nothing left to hire and only checks the page.
test("hiring a candidate creates the employee record", async ({ page }) => {
  await page.goto("/people/hiring?view=table");

  const main = page.getByRole("main");

  await main.locator('a[href*="/people/hiring/"]').first().click();
  await page.waitForURL((url) =>
    /\/people\/hiring\/[^/]+$/u.test(url.pathname),
  );

  const open = main.getByRole("button", { name: "Hire" });

  if (await open.isVisible()) {
    await open.click();
    await page
      .getByRole("dialog")
      .getByRole("button", { name: "Hire" })
      .click();
    await page.waitForURL((url) => /^\/people\/[^/]+$/u.test(url.pathname));
  }

  await expect(page.getByRole("main")).toBeVisible();
});
