import type { Locator, Page } from "@playwright/test";

import { writeFileSync, mkdirSync, existsSync, readFileSync } from "node:fs";
import { dirname } from "node:path";

import type { RouteEntry } from "../routes.manifest";

/** Signs in as the seeded Acme admin. */
export async function signIn(page: Page): Promise<void> {
  await page.goto("/login");
  await page.getByLabel("Email").fill("admin@acme.test");
  await page.getByLabel("Password").fill("password123");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL((url) => !url.pathname.endsWith("/login"));
}

/** The routes a spec can open without an id the seed does not fix. */
export function openableRoutes(
  routes: readonly RouteEntry[],
): readonly (RouteEntry & { readonly url: string })[] {
  return routes.flatMap((entry) =>
    entry.url === null ? [] : [{ ...entry, url: entry.url }],
  );
}

/** Where a spec leaves the numbers `scripts/example-perf-report.ts` merges. */
const PERF_DIR = "perf-results/example-perf";

/** Adds one measurement of a route to a JSON file under `PERF_DIR`. */
export function recordPerf(
  file: string,
  route: string,
  values: Readonly<Record<string, number>>,
): void {
  const path = `${PERF_DIR}/${file}`;
  mkdirSync(dirname(path), { recursive: true });

  // SAFETY: this file is only written by recordPerf, as route to numbers.
  const known: Record<string, Record<string, number>> = existsSync(path)
    ? (JSON.parse(readFileSync(path, "utf-8")) as Record<
        string,
        Record<string, number>
      >)
    : {};

  known[route] = { ...known[route], ...values };
  writeFileSync(path, JSON.stringify(known, null, 2));
}

/** Navigates in the browser the way a link click does, without a reload. */
export async function pushRoute(page: Page, url: string): Promise<void> {
  // The router exists only after hydration, and the load event fires before it.
  // A push before then does nothing, so a slow page timed out here (EX-024).
  await page.waitForFunction(() => {
    // SAFETY: Next.js exposes its router on `window.next` in the App Router.
    const next = (
      window as unknown as { next?: { router?: { push(href: string): void } } }
    ).next;

    return next?.router !== undefined;
  });
  // A push to a route that was never prefetched has no static shell to show
  // under the instant lock, so the navigation waits on the network instead.
  await page.evaluate(async (target) => {
    // SAFETY: Next.js exposes its router on `window.next` in the App Router.
    const next = (
      window as unknown as {
        next?: { router?: { prefetch(href: string): Promise<void> | void } };
      }
    ).next;

    await next?.router?.prefetch(target);
  }, url);
  await page.waitForTimeout(1000);
  await page.evaluate((target) => {
    // SAFETY: Next.js exposes its router on `window.next` in the App Router.
    const next = (
      window as unknown as { next?: { router?: { push(href: string): void } } }
    ).next;

    next?.router?.push(target);
  }, url);
  // A client navigation fires no load event, so waiting for one can hang.
  await page.waitForURL((current) => current.pathname === url, {
    waitUntil: "commit",
  });
}

/**
 * A side navigation link by its label. The menu groups its entries into
 * collapsible product areas and opens only the one that holds the current page,
 * so this opens `area` first when the link is not visible.
 */
export async function navLink(
  page: Page,
  name: string,
  area: string,
): Promise<Locator> {
  const link = page.getByRole("link", { name, exact: true }).first();

  if (!(await link.isVisible())) {
    await page.getByRole("button", { name: area, exact: true }).click();
  }

  return link;
}
