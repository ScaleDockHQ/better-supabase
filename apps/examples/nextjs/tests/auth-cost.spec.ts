/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import type { BrowserContext, Page, Response } from "@playwright/test";

import { expect, test } from "@playwright/test";
import { expectDbBudget } from "better-supabase/testing";

import { recordPerf, signIn, USERS } from "./support/example-session";
import type { Who } from "./support/example-session";

// What authentication and permissions cost, per scenario: the proxy's
// Server-Timing phases (`bsb-proxy`, `bsb-auth`, `bsb-verify`, `bsb-refresh`),
// the verified-session memo's hits and misses around the request, the document
// render's database calls, and wall time. The pass line of the repo standard:
// one session verification per request and at most one permission version read.
// Numbers go to auth-cost.json by scenario. Needs the production build with the
// testing API.

interface SessionStats {
  readonly hits: number;
  readonly misses: number;
}

const PAGES = ["/", "/customers", "/finance/invoices"] as const;

async function sessionStats(page: Page): Promise<SessionStats> {
  // SAFETY: the debug route answers with the memo's counters.
  return (await (await page.request.get("/api/bs-sessions")).json()) as SessionStats;
}

function timings(response: Response | null): Record<string, number> {
  const header = response?.headers()["server-timing"] ?? "";
  const metrics: Record<string, number> = {};

  for (const part of header.split(",")) {
    const [name, ...params] = part.trim().split(";");
    const dur = params.find((param) => param.trim().startsWith("dur="));

    if (name && dur) {
      metrics[`timing_${name.trim()}`] = Number(dur.trim().slice(4));
    }
  }

  return metrics;
}

/** Loads `url` once and returns what the request cost. */
async function measureLoad(
  page: Page,
  url: string,
): Promise<Record<string, number>> {
  const before = await sessionStats(page);
  let document: Response | null = null;
  const started = Date.now();

  const renders = await expectDbBudget(page, {
    during: async () => {
      document = await page.goto(url);
      await expect(page.getByRole("heading", { level: 1 }).first()).toBeVisible();
    },
    requireRequest: false,
  });

  const wall = Date.now() - started;
  const after = await sessionStats(page);

  return {
    wallMs: wall,
    calls: renders.reduce((sum, render) => sum + render.stats.calls, 0),
    waves: Math.max(0, ...renders.map((render) => render.stats.waves)),
    verifications: renders.reduce(
      (sum, render) => sum + render.stats.verifications,
      0,
    ),
    sessionHits: after.hits - before.hits,
    sessionMisses: after.misses - before.misses,
    ...timings(document),
  };
}

/** Rewrites the stored access token's expiry so the next request must refresh. */
async function expireAccessToken(context: BrowserContext): Promise<boolean> {
  const cookies = await context.cookies();
  const parts = cookies
    .filter((cookie) => /auth-token(\.\d+)?$/.test(cookie.name))
    .toSorted((a, b) => a.name.localeCompare(b.name));

  if (parts.length === 0) {
    return false;
  }

  const joined = parts.map((cookie) => decodeURIComponent(cookie.value)).join("");

  if (!joined.startsWith("base64-")) {
    return false;
  }

  const session = JSON.parse(
    Buffer.from(joined.slice("base64-".length), "base64url").toString("utf-8"),
    // SAFETY: @supabase/ssr stores the session as JSON in this cookie.
  ) as Record<string, unknown>;

  session["expires_at"] = 1;
  session["expires_in"] = 0;

  const value = `base64-${Buffer.from(JSON.stringify(session)).toString("base64url")}`;
  const first = parts[0];

  if (first === undefined) {
    return false;
  }

  await context.clearCookies({ name: /auth-token/ });
  const base = first.name.replace(/\.\d+$/, "");
  const CHUNK = 3000;
  const pieces: string[] = [];

  for (let at = 0; at < value.length; at += CHUNK) {
    pieces.push(value.slice(at, at + CHUNK));
  }

  await context.addCookies(
    pieces.map((piece, index) => ({
      name: pieces.length === 1 ? base : `${base}.${index}`,
      value: encodeURIComponent(piece),
      domain: first.domain,
      path: first.path,
      httpOnly: first.httpOnly,
      secure: first.secure,
      sameSite: first.sameSite,
    })),
  );

  return true;
}

for (const who of Object.keys(USERS) as Who[]) {
  test.describe(`as ${who}`, () => {
    test(`sign-in as ${who}`, async ({ page }) => {
      await page.goto("/login");
      await page.getByLabel("Email").fill(USERS[who]);
      await page.getByLabel("Password").fill("password123");

      const submit = page.getByRole("button", { name: "Sign in" });
      const started = Date.now();
      const responses: Response[] = [];
      page.on("response", (response) => responses.push(response));
      await submit.click();
      await page.waitForURL((url) => !url.pathname.endsWith("/login"));
      await expect(page.getByRole("heading", { level: 1 }).first()).toBeVisible();

      const roundTrips = responses.filter(
        (response) =>
          response.request().method() === "POST" ||
          response.request().resourceType() === "document",
      );

      recordPerf("auth-cost.json", `sign-in ${who}`, {
        wallMs: Date.now() - started,
        roundTrips: roundTrips.length,
        ...timings(roundTrips.at(-1) ?? null),
      });
    });

    for (const url of PAGES) {
      test(`warm ${url} as ${who}`, async ({ page }) => {
        await signIn(page, who);
        await page.goto(url);
        recordPerf("auth-cost.json", `warm ${url} ${who}`, await measureLoad(page, url));
      });
    }

    test(`expired access token on /customers as ${who}`, async ({
      page,
      context,
    }) => {
      await signIn(page, who);
      await page.goto("/customers");

      const expired = await expireAccessToken(context);
      test.skip(!expired, "the session cookie has an unexpected shape");

      recordPerf(
        "auth-cost.json",
        `refresh /customers ${who}`,
        await measureLoad(page, "/customers"),
      );
    });
  });
}
