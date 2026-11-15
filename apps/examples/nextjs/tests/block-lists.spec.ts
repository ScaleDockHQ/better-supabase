/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
/* oxlint-disable vitest/prefer-each -- Playwright has no test.each; the loop
   generates one case per list route (1 finding). */
import { expect, test } from "@playwright/test";

import { signIn } from "./support/example-session";

// The overviews that page a block's list (ADR 1077) answer every URL state
// from the database: the route passes the search, the filters, the sort and the
// cursor to the block's `page`, and `facets` counts each facet under them.

interface ListCase {
  readonly route: string;
  /** Query strings the list route has to answer with a page. */
  readonly queries: readonly string[];
}

const CASES: readonly ListCase[] = [
  {
    route: "/api/inventory/levels/list",
    queries: [
      "",
      "?sort=available",
      "?sort=on_hand&status=out",
      "?q=zzz-no-such-product",
    ],
  },
  {
    route: "/api/inventory/movements/list",
    queries: ["", "?sort=oldest", "?kind=stock.receipt", "?sort=quantity"],
  },
  {
    route: "/api/inventory/lots/list",
    queries: ["", "?sort=code", "?expiry=expired,soon", "?q=lot"],
  },
  {
    route: "/api/documents/register/list",
    queries: ["", "?sort=name", "?status=effective", "?review=due&sort=review"],
  },
  {
    route: "/api/qualifications/list",
    queries: ["", "?sort=key", "?state=active", "?expiry=never&q=a"],
  },
];

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

for (const { route, queries } of CASES) {
  for (const query of queries) {
    test(`${route}${query} answers a page`, async ({ page }) => {
      const response = await page.request.get(`${route}${query}`);

      expect(response.status()).toBe(200);

      const body: unknown = await response.json();

      expect(body).toMatchObject({ items: expect.any(Array) });
      expect(body).toHaveProperty("facetCounts");
    });
  }
}
