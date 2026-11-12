/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import { expect, test } from "@playwright/test";

// localePrefix is "as-needed": English has no prefix, Dutch keeps /nl. They need
// a `next build` and the local Supabase stack, like the other specs.

test("redirects the prefixed default locale to the unprefixed URL", async ({
  page,
}) => {
  await page.goto("/en/login");

  await expect(page).toHaveURL(/\/login$/);
  expect(new URL(page.url()).pathname).toBe("/login");
});

test("sends a signed-out visitor to the sign-in page of their locale", async ({
  page,
}) => {
  await page.goto("/projects");
  expect(new URL(page.url()).pathname).toBe("/login");

  await page.goto("/nl/projects");
  expect(new URL(page.url()).pathname).toBe("/nl/login");
});

test("follows the NEXT_LOCALE cookie to the Dutch sign-in page", async ({
  context,
  page,
}) => {
  await context.addCookies([
    { name: "NEXT_LOCALE", value: "nl", url: "http://localhost:3100" },
  ]);

  await page.goto("/projects");
  await page.waitForURL(/\/nl\/login/);

  expect(new URL(page.url()).pathname).toBe("/nl/login");
});

test("moves between /projects and /nl/projects with the language switcher", async ({
  page,
}) => {
  await page.goto("/login");
  await page.getByRole("textbox", { name: "Email" }).fill("admin@acme.test");
  await page.getByLabel("Password").fill("password123");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL((url) => !url.pathname.endsWith("/login"));

  await page.goto("/projects");
  expect(new URL(page.url()).pathname).toBe("/projects");

  await page.goto("/nl/projects");
  expect(new URL(page.url()).pathname).toBe("/nl/projects");
});

test("prefetches the home links by their own route after sign-in (EX-1511)", async ({
  page,
}) => {
  const failed: string[] = [];

  page.on("response", (response) => {
    if (response.url().includes("_rsc=") && response.status() >= 400) {
      failed.push(`${response.status()} ${response.url()}`);
    }
  });

  await page.goto("/login");
  await page.getByRole("textbox", { name: "Email" }).fill("admin@acme.test");
  await page.getByLabel("Password").fill("password123");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL((url) => !url.pathname.endsWith("/login"));

  // A sign-in that lands on a literal `/en` teaches the client that the first
  // path segment is the locale, and the next prefetch of `/my-work` asks for
  // the root page.
  expect(new URL(page.url()).pathname).toBe("/");
  await page.waitForLoadState("networkidle");

  expect(failed).toStrictEqual([]);
});
