import { expect, type Locator, type Page, test } from "@playwright/test";

import { clickSidebar, field, heading, visibleTestId } from "./nav";
import { fetchDelayMs } from "./server";
import { users } from "./users";

/**
 * Runs against the server whose Supabase requests wait `fetchDelayMs`
 * (`e2e/serve.ts`). Anything that shows in under a second came from the
 * static shell or a cache; a cold read shows after the delay.
 */
const instantMs = 1000;
const slowMs = fetchDelayMs - 500;

/** Milliseconds from starting `action` until `until` is visible. */
async function timed(
  label: string,
  action: () => Promise<void>,
  until: Locator,
): Promise<number> {
  const start = performance.now();
  await action();
  await expect(until).toBeVisible({ timeout: fetchDelayMs * 5 });
  const ms = Math.round(performance.now() - start);
  test.info().annotations.push({
    type: "timing",
    description: `${label}: ${String(ms)} ms`,
  });
  return ms;
}

/** A full page load that returns when the first byte arrives, not after the stream ends. */
function load(page: Page, path: string): () => Promise<void> {
  return async () => {
    await page.goto(path, { waitUntil: "commit" });
  };
}

function reload(page: Page): () => Promise<void> {
  return async () => {
    await page.reload({ waitUntil: "commit" });
  };
}

test.beforeAll(async ({ browser }) => {
  // The first signed-in request fetches the JWKS through the delayed fetch.
  const context = await browser.newContext({
    storageState: users.admin.storageState,
  });
  const page = await context.newPage();
  await page.goto("/en", { waitUntil: "commit" });
  await expect(visibleTestId(page, "workspace-summary")).toBeVisible({
    timeout: fetchDelayMs * 5,
  });
  await context.close();
});

test("the login page is static", async ({ page }) => {
  const ms = await timed(
    "login",
    load(page, "/en/login"),
    field(page, "Email"),
  );
  expect(ms).toBeLessThan(instantMs);
});

test.describe("owner", () => {
  test.use({ storageState: users.admin.storageState });

  test("a cold dashboard paints its shell at once and its data after the delay", async ({
    page,
  }) => {
    const start = performance.now();
    await page.goto("/en", { waitUntil: "commit" });
    await expect(heading(page, "Dashboard")).toBeVisible();
    const shell = Math.round(performance.now() - start);
    await expect(visibleTestId(page, "workspace-summary")).toBeVisible({
      timeout: fetchDelayMs * 5,
    });
    const data = Math.round(performance.now() - start);
    test
      .info()
      .annotations.push(
        { type: "timing", description: `dashboard shell: ${String(shell)} ms` },
        { type: "timing", description: `dashboard data: ${String(data)} ms` },
      );
    expect(shell).toBeLessThan(1500);
    expect(data).toBeGreaterThanOrEqual(slowMs);
  });

  test("customers are slow once, instant on the next visit and slow again on reload", async ({
    page,
  }) => {
    const roadRunner = page.getByRole("link", { name: "Road Runner Inc" });
    const first = await timed(
      "customers first load",
      load(page, "/en/customers"),
      roadRunner,
    );
    expect(first).toBeGreaterThanOrEqual(slowMs);

    await clickSidebar(page, "Dashboard", "/en")();
    await expect(visibleTestId(page, "workspace-summary")).toBeVisible({
      timeout: fetchDelayMs * 5,
    });
    const warm = await timed(
      "customers warm visit",
      clickSidebar(page, "Customers", "/en/customers"),
      roadRunner,
    );
    expect(warm).toBeLessThan(instantMs);

    const reloaded = await timed("customers reload", reload(page), roadRunner);
    expect(reloaded).toBeGreaterThanOrEqual(slowMs);
  });

  test("a repeated customer search paints from the browser's query cache", async ({
    page,
  }) => {
    await page.goto("/en/customers");
    await expect(
      page.getByRole("link", { name: "Road Runner Inc" }),
    ).toBeVisible({
      timeout: fetchDelayMs * 5,
    });
    // supabase-js in the browser talks to the Data API directly.
    await page.route("**/rest/v1/customers**", async (route) => {
      await new Promise((resolve) => {
        setTimeout(resolve, fetchDelayMs);
      });
      await route.continue();
    });
    const search = page.getByRole("searchbox", { name: "Search customers" });
    const results = page.getByTestId("customer-results");

    const start = performance.now();
    await search.fill("Road");
    await expect(results).toHaveAttribute("aria-busy", "true");
    await expect(results).toHaveAttribute("aria-busy", "false", {
      timeout: fetchDelayMs * 5,
    });
    const cold = Math.round(performance.now() - start);

    await search.fill("");
    const again = performance.now();
    await search.fill("Road");
    await expect(
      page.getByRole("link", { name: "Road Runner Inc" }),
    ).toBeVisible();
    await expect(results).toHaveAttribute("aria-busy", "false");
    const warm = Math.round(performance.now() - again);

    test
      .info()
      .annotations.push(
        { type: "timing", description: `search first: ${String(cold)} ms` },
        { type: "timing", description: `search again: ${String(warm)} ms` },
      );
    expect(cold).toBeGreaterThanOrEqual(slowMs);
    expect(warm).toBeLessThan(instantMs);
  });
});

test.describe("the shared plan catalog", () => {
  test("one user's visit fills it for the next user", async ({ browser }) => {
    const admin = await browser.newContext({
      storageState: users.admin.storageState,
    });
    const adminPage = await admin.newPage();
    await timed(
      "plans first load",
      load(adminPage, "/en/settings/billing"),
      visibleTestId(adminPage, "plan").first(),
    );
    const reloaded = await timed(
      "plans reload",
      reload(adminPage),
      visibleTestId(adminPage, "plan").first(),
    );
    expect(reloaded).toBeLessThan(instantMs);
    await admin.close();

    const member = await browser.newContext({
      storageState: users.member.storageState,
    });
    const memberPage = await member.newPage();
    const start = performance.now();
    await memberPage.goto("/en/settings/billing", { waitUntil: "commit" });
    await expect(visibleTestId(memberPage, "plan").first()).toBeVisible();
    const plans = Math.round(performance.now() - start);
    // The subscription is private, so it still waits for the database.
    await expect(visibleTestId(memberPage, "current-plan")).toBeVisible({
      timeout: fetchDelayMs * 5,
    });
    const subscription = Math.round(performance.now() - start);
    test.info().annotations.push(
      {
        type: "timing",
        description: `plans as another user: ${String(plans)} ms`,
      },
      {
        type: "timing",
        description: `subscription as another user: ${String(subscription)} ms`,
      },
    );
    expect(plans).toBeLessThan(instantMs);
    expect(subscription).toBeGreaterThanOrEqual(slowMs);
    await member.close();
  });
});
