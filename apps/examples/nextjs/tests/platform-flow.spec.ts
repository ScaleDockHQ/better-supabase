/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import { signIn } from "./support/example-session";

// The platform area: members with their seat figures, the API key detail with
// its rotation and the webhook endpoint detail with its deliveries.

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("the members page shows the seat figures and the seat-checked invite", async ({
  page,
}) => {
  await page.goto("/settings/members");

  const main = page.getByRole("main");

  await expect(
    main.getByTestId("kpi-band").filter({ visible: true }),
  ).toBeVisible();
  await expect(
    main.getByText("Seats left").filter({ visible: true }),
  ).toBeVisible();
  await expect(
    main.getByRole("button", { name: "Invite within seats" }),
  ).toBeVisible();
});

test("an API key opens instantly and rotates with a grace period", async ({
  page,
}) => {
  await page.goto("/settings/api-keys");

  const key = page.getByTestId("api-keys").getByRole("link").first();

  await expect(key).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await key.click();
      await page.waitForURL((url) =>
        /^\/settings\/api-keys\/[\da-f-]{36}$/.test(url.pathname),
      );
    },
    visible: [page.getByRole("link", { name: "All API keys" })],
  });

  const main = page.getByRole("main");

  await expect(
    main.getByText("Scopes").filter({ visible: true }),
  ).toBeVisible();

  await main.getByRole("button", { name: /Rotate, keep the old key/ }).click();
  await expect(main.getByTestId("rotated-token")).toBeVisible();
});

test("a webhook endpoint opens instantly with its deliveries", async ({
  page,
}) => {
  await page.goto("/settings/webhooks");

  const endpoint = page
    .getByTestId("webhook-endpoints")
    .getByRole("link")
    .first();

  await expect(endpoint).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await endpoint.click();
      await page.waitForURL((url) =>
        /^\/settings\/webhooks\/[\da-f-]{36}$/.test(url.pathname),
      );
    },
    visible: [page.getByRole("link", { name: "All webhooks" })],
  });

  const main = page.getByRole("main");

  await expect(
    main.getByTestId("kpi-band").filter({ visible: true }),
  ).toBeVisible();
  await expect(main.getByTestId("webhook-detail-deliveries")).toBeVisible();
});

// oxlint-disable-next-line vitest/prefer-each -- Playwright has no `test.each` (1 finding).
for (const path of ["/settings/api-keys", "/settings/webhooks"]) {
  test(`${path} shows its KPI band`, async ({ page }) => {
    await page.goto(path);
    await expect(
      page.getByRole("main").getByTestId("kpi-band").filter({ visible: true }),
    ).toBeVisible();
  });
}

test("a role opens instantly with its permission matrix", async ({ page }) => {
  await page.goto("/settings/roles");

  const link = page.getByRole("link", { name: "Admin" }).first();

  await expect(link).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) =>
        /^\/settings\/roles\/[^/]+$/.test(url.pathname),
      );
    },
    visible: [page.getByRole("link", { name: "All roles" })],
  });

  const main = page.getByRole("main");

  await expect(
    main.getByTestId("kpi-band").filter({ visible: true }),
  ).toBeVisible();
  await expect(
    main.getByText("Permission matrix").filter({ visible: true }),
  ).toBeVisible();
});

test("a member opens instantly with the seat view", async ({ page }) => {
  await page.goto("/settings/members");

  const link = page
    .getByRole("main")
    .locator('a[href*="/settings/members/"]')
    .first();

  await expect(link).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) =>
        /^\/settings\/members\/[^/]+$/.test(url.pathname),
      );
    },
    visible: [page.getByRole("link", { name: "All members" })],
  });

  const main = page.getByRole("main");

  await expect(
    main.getByTestId("member-detail").getByText("Seats used"),
  ).toBeVisible();
  await expect(
    main.getByText("Seats left").filter({ visible: true }),
  ).toBeVisible();
});

test("the signing keys page links the public JWK Set, which answers without a session", async ({
  page,
  playwright,
}) => {
  await page.goto("/settings/signing-keys");

  const link = page
    .getByRole("main")
    .getByRole("link", { name: /^\/\.well-known\/jwks\// });

  const path = await link.getAttribute("href");

  expect(path).not.toBeNull();

  const anonymous = await playwright.request.newContext({
    baseURL: new URL(page.url()).origin,
  });

  const response = await anonymous.get(path ?? "");

  expect(response.status()).toBe(200);
  expect(response.headers()["content-type"]).toContain("json");
  expect((await response.json()) as unknown).toMatchObject({
    keys: expect.any(Array) as unknown,
  });
  await anonymous.dispose();
});

// oxlint-disable-next-line vitest/prefer-each -- Playwright has no test.each (1 finding)
for (const [path, label] of [
  ["/settings/signing-keys", "Active key"],
  ["/settings/billing", "Renews"],
  ["/settings/preferences", "Organization settings"],
] as const) {
  test(`${path} shows its KPI band`, async ({ page }) => {
    await page.goto(path);

    await expect(
      page.getByRole("main").getByTestId("kpi-band").getByText(label),
    ).toBeVisible();
  });
}
