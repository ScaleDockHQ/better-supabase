/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals. */
import type { Page } from "@playwright/test";

import { expect, test } from "@playwright/test";

// The JavaScript a cold visit downloads, decoded, counted as the browser
// fetches it. `tests/next-build` holds the static first load to a baseline;
// this one adds the chunks a route pulls in while it hydrates, so a lazy chunk
// that every visit fetches anyway shows up here (ADR 0480).

// Measured on a production build: /en/login 824231 and /en/signup 786287 decoded
// bytes (700 KB of static first load plus the toaster and the lazy chunks that
// load while it hydrates). The budget leaves about 3% for chunk changes.
const SIGN_IN_BUDGET = 850_000;

async function scriptBytes(page: Page, path: string): Promise<number> {
  const sizes: Promise<number>[] = [];

  page.on("response", (response) => {
    if (
      response.url().includes("/_next/static/chunks/") &&
      response.url().endsWith(".js")
    ) {
      sizes.push(response.body().then((body) => body.length));
    }
  });

  await page.goto(path, { waitUntil: "networkidle" });

  const total = (await Promise.all(sizes)).reduce((sum, size) => sum + size, 0);

  test
    .info()
    .annotations.push({ type: "script bytes", description: `${total}` });
  console.log(`script bytes ${path}: ${total}`);

  return total;
}

test("the sign-in route downloads a small amount of JavaScript", async ({
  page,
}) => {
  const bytes = await scriptBytes(page, "/en/login");

  expect(bytes, "sign-in script bytes").toBeLessThan(SIGN_IN_BUDGET);
});

test("the sign-up route downloads a small amount of JavaScript", async ({
  page,
}) => {
  const bytes = await scriptBytes(page, "/en/signup");

  expect(bytes, "sign-up script bytes").toBeLessThan(SIGN_IN_BUDGET);
});
