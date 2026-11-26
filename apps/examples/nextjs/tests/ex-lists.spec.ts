import type { Page as BrowserPage } from "@playwright/test";

import { expect, test } from "@playwright/test";

import { signIn } from "./support/example-session";

// The pages that moved onto the list calls of EX-800, EX-802, EX-1102 and
// EX-1103: gifts search through `giftPage`, the moderation queue asks for a
// list of statuses in one call, and the warehouse and request pages read their
// lookups from the inventory block's lists.

interface Page {
  readonly items: readonly { readonly id: string }[];
  readonly nextCursor: string | null;
}

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

async function read(page: BrowserPage, url: string): Promise<Page> {
  const response = await page.request.get(url);

  expect(response.status()).toBe(200);

  const body: Page = await response.json();

  expect(body).toMatchObject({ items: expect.any(Array) });

  return body;
}

test("the gifts list answers q and a list of statuses", async ({ page }) => {
  const all = await read(page, "/api/donations/list");
  const none = await read(page, "/api/donations/list?q=zzz-no-such-gift");
  const two = await read(page, "/api/donations/list?status=posted,refunded");

  expect(none.items).toHaveLength(0);
  expect(two.items.length).toBeLessThanOrEqual(all.items.length);
});

test("the moderation queue takes several statuses in one call", async ({
  page,
}) => {
  const pending = await read(page, "/api/reviews/list?status=pending");
  const rejected = await read(page, "/api/reviews/list?status=rejected");
  const both = await read(page, "/api/reviews/list?status=pending,rejected");

  expect(both.items.map((row) => row.id).toSorted()).toEqual(
    [...pending.items, ...rejected.items].map((row) => row.id).toSorted(),
  );
});

for (const route of [
  "/shop/donations?q=zzz-no-such-gift",
  "/shop/reviews?status=pending&status=rejected",
  "/warehouse",
  "/warehouse?q=zzz-no-such-list",
  "/warehouse?tab=waves",
  "/rfqs",
]) {
  test(`${route} renders without a load error`, async ({ page }) => {
    const response = await page.goto(route);

    expect(response?.status()).toBeLessThan(400);
    await expect(page.getByRole("main")).toBeVisible();
    await expect(page.getByText("didn't load")).toHaveCount(0);
  });
}

test("the pick list overview searches by document", async ({ page }) => {
  await page.goto("/warehouse");

  const search = page.getByRole("main").getByRole("searchbox");

  await expect(search).toBeVisible();
  await search.fill("zzz-no-such-list");
  await expect(page.getByText("No pick lists found")).toBeVisible();
});
