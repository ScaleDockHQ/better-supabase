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
  {
    route: "/api/employees/list",
    queries: ["", "?sort=start", "?status=active", "?q=a&status=on_leave"],
  },
  {
    route: "/api/leave/list",
    queries: ["", "?sort=newest", "?status=pending", "?q=holiday&type=none"],
  },
  {
    route: "/api/onboarding/list",
    queries: ["", "?sort=updated", "?status=active", "?q=onboarding"],
  },
  {
    route: "/api/deadlines/list",
    queries: ["", "?sort=newest", "?state=pending", "?result=due&group=none"],
  },
  {
    route: "/api/document-templates/list",
    queries: ["", "?sort=newest", "?active=true", "?type=invoice&q=a"],
  },
];

/** Overviews whose rows link to a detail page the list's first row opens. */
const DETAILS: readonly { readonly list: string; readonly href: string }[] = [
  { list: "/api/document-templates/list", href: "/documents/templates/" },
  { list: "/api/leave/list", href: "/people/leave/" },
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

for (const { list, href } of DETAILS) {
  test(`${list} first row opens its detail page`, async ({ page }) => {
    const response = await page.request.get(list);
    const body: { items: readonly { id: string }[] } = await response.json();
    const first = body.items[0];

    test.skip(first === undefined, "the seed has no row here");

    if (first !== undefined) {
      const detail = await page.goto(`${href}${first.id}`);

      expect(detail?.status()).toBe(200);
      await expect(
        page.getByRole("heading", { level: 1 }).first(),
      ).toBeVisible();
    }
  });
}
