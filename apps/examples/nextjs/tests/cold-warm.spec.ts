import { expect, test } from "@playwright/test";

import { ROUTES } from "./routes.manifest";
import {
  openableRoutes,
  perfUser,
  prefetchRoute,
  pushRoute,
  recordPerf,
  signIn,
} from "./support/example-session";

// The first hit of each route after a server start (empty caches), the second
// hit (warm), and a client navigation to it from the dashboard. Run this spec
// first against a freshly started server, or the first hit is already warm.
// The ceilings are generous on purpose; tighten them from the measured numbers
// in perf-results/example-perf/cold-warm.json.

const CEILING_MS = { cold: 20_000, warm: 5000, client: 3000 } as const;

test.beforeEach(async ({ page }) => {
  await signIn(page, perfUser());
});

async function timed(action: () => Promise<void>): Promise<number> {
  const start = Date.now();
  await action();

  return Date.now() - start;
}

for (const entry of openableRoutes(ROUTES)) {
  test(`${entry.route} cold, warm and client navigation`, async ({ page }) => {
    const heading = page.getByRole("heading", { level: 1 }).first();

    const cold = await timed(async () => {
      await page.goto(entry.url);
      await expect(heading).toBeVisible();
    });

    const warm = await timed(async () => {
      await page.goto(entry.url);
      await expect(heading).toBeVisible();
    });

    await page.goto("/");
    await prefetchRoute(page, entry.url);

    const client = await timed(async () => {
      await pushRoute(page, entry.url);
      await expect(heading).toBeVisible();
    });

    recordPerf(
      `cold-warm${perfUser() === "admin" ? "" : `-${perfUser()}`}.json`,
      entry.route,
      { cold, warm, client },
    );

    expect(cold).toBeLessThan(CEILING_MS.cold);
    expect(warm).toBeLessThan(CEILING_MS.warm);
    expect(client).toBeLessThan(CEILING_MS.client);
  });
}
