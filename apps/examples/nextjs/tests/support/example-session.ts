import type { Locator, Page } from "@playwright/test";

import { writeFileSync, mkdirSync, existsSync, readFileSync } from "node:fs";
import { dirname } from "node:path";

import type { RouteEntry } from "../routes.manifest";

/** The seeded Acme users the harness signs in as. */
export const USERS = {
  admin: "admin@acme.test",
  member: "member@acme.test",
} as const;

export type Who = keyof typeof USERS;

/** Signs in as a seeded Acme user; the admin by default. */
export async function signIn(page: Page, who: Who = "admin"): Promise<void> {
  await page.goto("/login");
  await page.getByLabel("Email").fill(USERS[who]);
  await page.getByLabel("Password").fill("password123");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL((url) => !url.pathname.endsWith("/login"));
}

/** The harness user of this run: `BSB_PERF_USER=member` measures as the member. */
export function perfUser(): Who {
  return process.env["BSB_PERF_USER"] === "member" ? "member" : "admin";
}

/** The routes whose URL `resolve-urls.spec.ts` found, by manifest route. */
function resolvedUrls(): Readonly<Record<string, string>> {
  const path = `${PERF_DIR}/urls.json`;

  // SAFETY: this file is only written by resolve-urls.spec.ts, as route to url.
  return existsSync(path)
    ? (JSON.parse(readFileSync(path, "utf-8")) as Record<string, string>)
    : {};
}

/** Adds the URL `resolve-urls.spec.ts` found for `route`. */
export function recordUrl(route: string, url: string): void {
  const path = `${PERF_DIR}/urls.json`;
  mkdirSync(dirname(path), { recursive: true });
  const known = { ...resolvedUrls(), [route]: url };
  writeFileSync(path, JSON.stringify(known, null, 2));
}

/**
 * The routes a spec can open: those with a fixed URL and those whose URL the
 * resolve spec found by following a link from the list page.
 */
export function openableRoutes(
  routes: readonly RouteEntry[],
): readonly (RouteEntry & { readonly url: string })[] {
  const found = resolvedUrls();

  return routes.flatMap((entry) => {
    const url = entry.url ?? found[entry.route];

    return url === undefined ? [] : [{ ...entry, url }];
  });
}

/**
 * Where a spec leaves the numbers `scripts/example-perf-report.ts` merges.
 * `BSB_PERF_DIR` keeps a run apart, for instance a member or a tier L run.
 */
const PERF_DIR = process.env["BSB_PERF_DIR"] ?? "perf-results/example-perf";

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

/** Waits for the router, then asks it to prefetch `url` and lets that settle. */
export async function prefetchRoute(
  page: Page,
  url: string,
  settleMs = 1000,
): Promise<void> {
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
  await page.waitForTimeout(settleMs);
}

/**
 * Navigates in the browser the way a link click does, without a reload. Call
 * `prefetchRoute` first and keep it outside a timer, so a timing holds only the
 * navigation.
 */
export async function pushRoute(page: Page, url: string): Promise<void> {
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
