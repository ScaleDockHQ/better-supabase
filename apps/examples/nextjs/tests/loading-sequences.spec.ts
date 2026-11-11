/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import type { Page } from "@playwright/test";

import { instant } from "@next/playwright";
import { expect, test } from "@playwright/test";

import { navLink } from "./support/example-session";

// Each test states which content is visible before uncached work resolves
// (under `instant()`'s lock) and which streams in after it. They need a `next
// build` with the testing API exposed, like instant.spec.ts, and the local
// Supabase stack with the seeded users.

async function signIn(page: Page): Promise<void> {
  await page.goto("/login");
  await page.getByRole("textbox", { name: "Email" }).fill("admin@acme.test");
  await page.getByLabel("Password").fill("password123");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL((url) => !url.pathname.endsWith("/login"));
}

test("the customers list paints its heading before the rows", async ({
  page,
}) => {
  await signIn(page);
  await page.goto("/");
  const link = await navLink(page, "Customers", "Sales");

  await expect(link.first()).toBeVisible();

  await instant(page, async () => {
    await link.first().click();
    await page.waitForURL((url) => url.pathname === "/customers");

    await expect(
      page.getByRole("heading", { name: "Customers" }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: "Road Runner Inc" }),
    ).toHaveCount(0);
  });

  await expect(
    page.getByRole("link", { name: "Road Runner Inc" }),
  ).toBeVisible();
});

test("a customer shows its head before the side sections", async ({ page }) => {
  await signIn(page);
  await page.goto("/customers");
  const row = page.getByRole("link", { name: "Road Runner Inc" });

  await expect(row).toBeVisible();

  await instant(page, async () => {
    await row.click();
    await page.waitForURL((url) => url.pathname.startsWith("/customers/"));

    await expect(
      page.getByRole("link", { name: "All customers" }),
    ).toBeVisible();
    // The versions and timeline cards await navigation(), so the per-link
    // prefetch leaves them out of the locked render.
    await expect(page.getByText("Version history")).toHaveCount(0);
    await expect(page.getByText("Timeline", { exact: true })).toHaveCount(0);
  });

  await expect(page.getByText("Version history")).toBeVisible();
  await expect(page.getByText("Timeline", { exact: true })).toBeVisible();
});

test("the sign-in form is static and the sign-up link is instant", async ({
  page,
}) => {
  await page.goto("/login");
  const signUp = page.getByRole("link", { name: "Sign up" });

  await expect(signUp).toBeVisible();

  await instant(page, async () => {
    await signUp.click();
    await page.waitForURL((url) => url.pathname === "/signup");

    await expect(page.getByRole("textbox", { name: "Email" })).toBeVisible();
  });
});

test("the sign-up form is static and the sign-in link is instant", async ({
  page,
}) => {
  await page.goto("/signup");
  const signIn = page.getByRole("link", { name: "Sign in" });

  await expect(signIn).toBeVisible();

  await instant(page, async () => {
    await signIn.click();
    await page.waitForURL((url) => url.pathname === "/login");

    await expect(page.getByRole("textbox", { name: "Email" })).toBeVisible();
  });
});

test("the assistant paints its heading before the chats", async ({ page }) => {
  await signIn(page);
  await page.goto("/");
  const link = await navLink(page, "Assistant", "AI");

  await expect(link.first()).toBeVisible();

  await instant(page, async () => {
    await link.first().click();
    await page.waitForURL((url) => url.pathname === "/assistant");

    await expect(
      page.getByRole("heading", { name: "Assistant" }),
    ).toBeVisible();
  });
});

test("the projects frame paints before the project data", async ({ page }) => {
  await signIn(page);
  await page.goto("/");
  const link = await navLink(page, "Projects", "Work");

  await expect(link.first()).toBeVisible();

  await instant(page, async () => {
    await link.first().click();
    await page.waitForURL((url) => url.pathname === "/projects");

    await expect(page.getByRole("heading", { name: "Projects" })).toBeVisible();
  });
});

test("a customer search keeps the grid and writes the URL", async ({
  page,
}) => {
  await signIn(page);
  await page.goto("/customers");

  const search = page.getByRole("searchbox", { name: "Search customers" });
  const row = page.getByRole("link", { name: "Road Runner Inc" });

  await expect(row).toBeVisible();
  await search.fill("Road");

  await expect(page).toHaveURL(/[?&]q=Road/);
  await expect(row).toBeVisible();
  await expect(page.getByTestId("record-list")).toBeVisible();
});

test("the risks overview paints its heading before the register", async ({
  page,
}) => {
  await signIn(page);
  await page.goto("/");
  const link = await navLink(page, "Risks", "Quality");

  await expect(link.first()).toBeVisible();

  await instant(page, async () => {
    await link.first().click();
    await page.waitForURL((url) => url.pathname === "/risks");

    await expect(page.getByRole("heading", { name: "Risks" })).toBeVisible();
    await expect(page.getByTestId("record-list")).toHaveCount(0);
  });

  await expect(page.getByTestId("record-list")).toBeVisible();
});

test("the warranty overview paints its heading before the claims", async ({
  page,
}) => {
  await signIn(page);
  await page.goto("/");
  const link = await navLink(page, "Warranty", "Commerce");

  await expect(link.first()).toBeVisible();

  await instant(page, async () => {
    await link.first().click();
    await page.waitForURL((url) => url.pathname === "/shop/warranty");

    await expect(
      page.getByRole("heading", { name: "Warranty claims" }),
    ).toBeVisible();
    await expect(page.getByTestId("record-list")).toHaveCount(0);
  });

  await expect(page.getByTestId("record-list")).toBeVisible();
});

test("a risk search writes the URL and keeps the register", async ({
  page,
}) => {
  await signIn(page);
  await page.goto("/risks");

  const search = page.getByRole("searchbox", { name: "Search risks" });

  await expect(page.getByTestId("record-list")).toBeVisible();
  await search.fill("supplier");

  await expect(page).toHaveURL(/[?&]q=supplier/);
  await expect(page.getByTestId("record-list")).toBeVisible();
});

test("the inbox keeps its queue while a conversation opens", async ({
  page,
}) => {
  await signIn(page);
  await page.goto("/inbox");
  const row = page.getByRole("link", { name: /Invoice 1042 is overdue/ });

  await expect(row).toBeVisible();

  await instant(page, async () => {
    await row.click();
    await page.waitForURL((url) => url.pathname.startsWith("/inbox/"));

    // The queue is the layout, so it stays; the thread streams in after it.
    await expect(
      page.getByRole("searchbox", { name: "Search conversations" }),
    ).toBeVisible();
    await expect(page.getByText("Earlier conversations")).toHaveCount(0);
  });

  await expect(page.getByText("Earlier conversations")).toBeVisible();
  await expect(page.getByRole("textbox", { name: "Reply" })).toBeVisible();
});
