import type { APIRequestContext } from "@playwright/test";

import { instant } from "@next/playwright";
import { expect, test } from "@playwright/test";

import { heading, visibleTestId } from "./nav";
import { baseURL } from "./server";
import { users } from "./users";

interface MemoStats {
  readonly hits: number;
  readonly misses: number;
  readonly size: number;
}

async function memoStats(request: APIRequestContext): Promise<MemoStats> {
  const response = await request.get("/api/bs-sessions");

  expect(response.ok()).toBe(true);

  // SAFETY: the route returns `bsb.sessions.stats()` as JSON.
  return (await response.json()) as MemoStats;
}

const islands = [
  "island-customers",
  "island-notes",
  "island-contacts",
  "island-tags",
  "island-tasks",
  "island-email",
  "island-organization",
  "island-expires",
  "island-issued",
  "island-version",
];

test.describe("ten private islands", () => {
  test.use({ storageState: users.admin.storageState });

  test("the page serves its static shell", async ({ page }) => {
    await instant(
      page,
      async () => {
        await page.goto("/en/islands");
        await expect(heading(page, "Islands")).toBeVisible();
        // Every island reads the session, so none is in the static shell.
        await expect(page.getByTestId("island-email")).toHaveCount(0);
      },
      { baseURL },
    );

    for (const id of islands) {
      await expect(visibleTestId(page, id)).toBeVisible();
    }
  });

  test("ten islands verify the token at most once", async ({ page }) => {
    const before = await memoStats(page.request);

    await page.goto("/en/islands");

    for (const id of islands) {
      await expect(visibleTestId(page, id)).toBeVisible();
    }

    const after = await memoStats(page.request);

    expect(after.misses - before.misses).toBeLessThanOrEqual(1);
    await expect(page.getByTestId("island-error")).toHaveCount(0);
  });

  test("a hard load makes no Auth call", async ({ page }) => {
    const response = await page.goto("/en/islands");

    const timing = (await response?.allHeaders())?.["server-timing"] ?? "";

    expect(timing).toContain("bsb-proxy");
    expect(timing).not.toContain("bsb-refresh");
    expect(timing).not.toContain("bsb-ended");
  });

  test("a prefetch leaves the session cookies alone", async ({ page }) => {
    await page.goto("/en");

    const response = await page.request.get("/en/islands", {
      headers: { "sec-purpose": "prefetch" },
    });

    expect(response.status(), await response.text()).toBe(200);
    expect(response.headers()["set-cookie"] ?? "").not.toMatch(/sb-.*auth/u);
    expect(response.headers()["server-timing"] ?? "").not.toContain(
      "bsb-refresh",
    );
  });
});
