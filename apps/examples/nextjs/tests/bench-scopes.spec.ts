/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import type { APIRequestContext, Page } from "@playwright/test";

import { expect, test } from "@playwright/test";

const EMAIL = "admin@acme.test";
const SCOPES = 12;

interface SessionStats {
  readonly hits: number;
  readonly misses: number;
}

async function signIn(page: Page): Promise<void> {
  await page.goto("/en/login");
  await page.getByLabel("Email").fill(EMAIL);
  await page.getByLabel("Password").fill("password123");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL((url) => !url.pathname.endsWith("/login"));
}

async function lookups(request: APIRequestContext): Promise<number> {
  const stats: SessionStats = await (
    await request.get("/api/bs-sessions")
  ).json();

  return stats.hits + stats.misses;
}

/** Memo lookups and misses one load of the page makes. */
async function load(page: Page, variant: "plain" | "session") {
  const before = await page.request.get("/api/bs-sessions");
  const start: SessionStats = await before.json();

  await page.goto(`/en/bench/scopes?variant=${variant}`);
  // React streams each Suspense boundary into a hidden `div` before it swaps
  // the content into the list, so the id briefly exists twice; scope to the list.
  await expect(
    page.getByRole("list").getByTestId(`scope-${SCOPES - 1}`),
  ).toBeVisible();

  const end: SessionStats = await (
    await page.request.get("/api/bs-sessions")
  ).json();

  return {
    lookups: end.hits + end.misses - (start.hits + start.misses),
    misses: end.misses - start.misses,
  };
}

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("twelve private scopes verify at most once", async ({ page }) => {
  const plain = await load(page, "plain");

  test
    .info()
    .annotations.push({
      type: "plain",
      description: `${String(plain.lookups)} lookups, ${String(plain.misses)} misses`,
    });

  expect(plain.misses).toBeLessThanOrEqual(1);
  expect(plain.lookups).toBeGreaterThanOrEqual(SCOPES);
});

test("a session handle makes the scopes verify zero times", async ({
  page,
}) => {
  const session = await load(page, "session");

  test
    .info()
    .annotations.push({
      type: "session",
      description: `${String(session.lookups)} lookups, ${String(session.misses)} misses`,
    });

  expect(session.misses).toBe(0);
  // The proxy's own resolution and the one `bsb.sessionHandle()` call, no more.
  expect(session.lookups).toBeLessThanOrEqual(SCOPES / 2);
  expect(await lookups(page.request)).toBeGreaterThan(0);
});
