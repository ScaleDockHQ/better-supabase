/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import type { APIRequestContext, Page } from "@playwright/test";

import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";
import { Client } from "pg";
import * as v from "valibot";

// The second `next start` playwright.config.ts runs on the same build and
// remote cache directory.
const SECOND_ORIGIN = "http://localhost:3101";

const EMAIL = "admin@acme.test";

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

async function sessionStats(
  request: APIRequestContext,
  origin = "",
): Promise<SessionStats> {
  return (await request.get(`${origin}/api/bs-sessions`)).json();
}

// Scoped to the page's `<main>`: a hidden copy of a streamed boundary can sit
// beside it until hydration moves it in.
function island(page: Page, id: string) {
  return page.getByRole("main").getByTestId(`island-${id}`);
}

async function cachedAt(page: Page): Promise<string | null> {
  const status = page.getByRole("main").getByTestId("islands-cached-at");

  await expect(status).toBeVisible();

  return status.getAttribute("datetime");
}

async function version(page: Page): Promise<string> {
  return (await island(page, "version-value").textContent()) ?? "";
}

// A Phoenix `[join_ref, ref, topic, event, payload]` text frame. Broadcasts
// can arrive as binary frames, which never match.
const Frame = v.pipe(
  v.string(),
  v.parseJson(),
  v.tuple([
    v.nullable(v.string()),
    v.nullable(v.string()),
    v.string(),
    v.string(),
    v.unknown(),
  ]),
);

const JoinReply = v.object({ status: v.literal("ok") });

/** Resolves once Realtime accepts the page's join to its `authz:<uid>` topic. */
function authzJoined(page: Page): Promise<void> {
  return new Promise((resolve) => {
    page.on("websocket", (socket) => {
      const joins = new Set<string | null>();

      socket.on("framesent", ({ payload }) => {
        const frame = v.safeParse(Frame, payload);

        if (!frame.success) {
          return;
        }

        const [, ref, topic, event] = frame.output;

        if (event === "phx_join" && topic.startsWith("realtime:authz:")) {
          joins.add(ref);
        }
      });

      socket.on("framereceived", ({ payload }) => {
        const frame = v.safeParse(Frame, payload);

        if (!frame.success) {
          return;
        }

        const [, ref, , event, body] = frame.output;

        if (event === "phx_reply" && joins.has(ref) && v.is(JoinReply, body)) {
          resolve();
        }
      });
    });
  });
}

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("a page load makes one bootstrap call and at most one verification", async ({
  page,
}) => {
  const before = await sessionStats(page.request);
  const response = await page.goto("/en/islands");

  await expect(island(page, "email")).toBeVisible();
  await expect(island(page, "customers")).toBeVisible();

  const statsUrl = response?.headers()["x-bsb-stats"];

  expect(statsUrl).toBeDefined();

  const stats = await (await page.request.get(statsUrl!)).json();

  // Ten islands and the header, one `bootstrap_islands` call.
  expect(stats.calls).toBe(1);
  expect(stats.waves).toBe(1);

  const after = await sessionStats(page.request);

  expect(after.misses - before.misses).toBeLessThanOrEqual(1);
});

test("the islands shell renders under the instant lock", async ({ page }) => {
  await page.goto("/en/customers");
  const link = page.getByRole("link", { name: "Islands", exact: true });

  await expect(link.first()).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.first().click();
      await page.waitForURL((url) => url.pathname === "/en/islands");
    },
    visible: [page.getByRole("heading", { name: "Islands", exact: true })],
  });

  await expect(island(page, "customers")).toBeVisible();
});

test("a version bump refreshes the islands in the background", async ({
  page,
}) => {
  const joined = authzJoined(page);

  await page.goto("/en/islands");
  await expect(island(page, "version-value")).toBeVisible();
  // Realtime doesn't replay a broadcast sent before the join.
  await joined;

  const start = Number(await version(page));
  await page.evaluate(() => {
    document.documentElement.dataset["islandsLoad"] = "first";
  });

  const { SUPABASE_DB_URL: connectionString } = process.env;
  const client = new Client({ connectionString });

  await client.connect();

  try {
    await client.query(
      "select better_supabase.bump_authz_versions(array(select id from auth.users where email = $1))",
      [EMAIL],
    );
  } finally {
    await client.end();
  }

  await expect
    .poll(async () => Number(await version(page)), { timeout: 20_000 })
    .toBeGreaterThan(start);

  // The same document: the refresh re-rendered, it didn't reload.
  expect(
    await page.evaluate(() => document.documentElement.dataset["islandsLoad"]),
  ).toBe("first");
});

test("a second instance serves the remote entry and both drop it on evict", async ({
  page,
}) => {
  await expect
    .poll(
      async () => (await page.request.get(`${SECOND_ORIGIN}/en/login`)).ok(),
      { timeout: 120_000 },
    )
    .toBe(true);

  await page.goto("/en/islands?scope=remote");
  const first = await cachedAt(page);

  const response = await page.goto(`${SECOND_ORIGIN}/en/islands?scope=remote`);

  expect(await cachedAt(page)).toBe(first);

  // A remote hit: the second instance made no database call.
  const statsUrl = response?.headers()["x-bsb-stats"];

  const stats = await (
    await page.request.get(`${SECOND_ORIGIN}${statsUrl}`)
  ).json();

  expect(stats.calls).toBe(0);

  await page.getByRole("button", { name: "Evict my cached views" }).click();
  await expect.poll(() => cachedAt(page), { timeout: 10_000 }).not.toBe(first);

  await page.goto("/en/islands?scope=remote");
  expect(await cachedAt(page)).not.toBe(first);
});

test("a signed-in user on the sign-in page goes to ?next=", async ({
  page,
}) => {
  await page.goto("/en/login?next=/en/islands");
  await page.waitForURL((url) => url.pathname === "/en/islands");
  await expect(
    page.getByRole("heading", { name: "Islands", exact: true }),
  ).toBeVisible();
});
