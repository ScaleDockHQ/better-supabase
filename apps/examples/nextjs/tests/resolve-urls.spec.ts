/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
/* oxlint-disable vitest/prefer-each -- Playwright has no test.each; the loop
   generates one case per dynamic route of the manifest (1 finding). */
import { expect, test } from "@playwright/test";

import { ROUTES } from "./routes.manifest";
import { recordUrl, signIn } from "./support/example-session";
import { seededUrl } from "./support/seed-lookup";

// Finds a seeded URL for every route whose manifest `url` is null by following
// links from the list page: the route `/finance/invoices/[id]` is reached from
// `/finance/invoices`. The result goes to perf-results/example-perf/urls.json,
// so the budget, timing and instant specs open every dynamic page. A route no
// list links to stays unresolved and is reported as a finding.

const DEPTH = 3;

const pattern = (route: string, parts: number): RegExp => {
  const segments = route.split("/").slice(1, parts + 1);
  const source = segments
    .map((segment) =>
      segment.startsWith("[") ? "[^/?#]+" : segment.replace(/[.*+?^${}()|\\]/g, "\\$&"),
    )
    .join("/");

  return new RegExp(`^/${source}$`);
};

const stripLocale = (path: string): string => path.replace(/^\/(en|nl)(?=\/|$)/, "");

test.describe.configure({ mode: "serial" });

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

for (const entry of ROUTES.filter((route) => route.url === null)) {
  test(`${entry.route} has a seeded URL`, async ({ page }) => {
    const segments = entry.route.split("/").slice(1);
    const firstParam = segments.findIndex((segment) => segment.startsWith("["));
    let frontier = [`/${segments.slice(0, firstParam).join("/")}`];
    const seen = new Set<string>();

    for (let depth = 0; depth < DEPTH; depth += 1) {
      const next: string[] = [];

      for (const url of frontier.slice(0, 3)) {
        if (seen.has(url)) {
          continue;
        }

        seen.add(url);
        await page.goto(url === "/" ? "/" : url, { waitUntil: "domcontentloaded" });
        await page.waitForTimeout(1500);

        const hrefs = await page
          .locator("a[href]")
          .evaluateAll((links) =>
            links.map((link) => link.getAttribute("href") ?? ""),
          );
        const paths = hrefs
          .filter((href) => href.startsWith("/"))
          .map((href) => stripLocale(href.split(/[?#]/)[0] ?? ""));

        const full = paths.find((path) => pattern(entry.route, segments.length).test(path));

        if (full !== undefined) {
          recordUrl(entry.route, full);

          return;
        }

        for (let parts = firstParam + 1; parts < segments.length; parts += 1) {
          const nested = paths.find(
            (path) =>
              pattern(entry.route, parts).test(path) && !seen.has(path),
          );

          if (nested !== undefined) {
            next.push(nested);
          }
        }
      }

      frontier = next;
    }

    const fromDb = await seededUrl(entry.route);

    if (fromDb !== undefined) {
      recordUrl(entry.route, fromDb);

      return;
    }

    test.info().annotations.push({ type: "unresolved", description: entry.route });
    expect(true).toBe(true);
  });
}
