/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import type { Page, Response } from "@playwright/test";

import { expect, test } from "@playwright/test";

/**
 * Payload of a signed-in production render: decoded HTML, inline Flight
 * (`self.__next_f`), bytes that look like serialized claims or permissions, and
 * the collector header (`x-bsb-stats` is calls;waves;ms;verifications;admin).
 * Waves are the round trips the collector counted.
 */

async function signIn(page: Page): Promise<void> {
  await page.goto("/login");
  await page.getByLabel("Email").fill("admin@acme.test");
  await page.getByLabel("Password").fill("password123");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL((url) => !url.pathname.endsWith("/login"));
}

function flightBytes(html: string): number {
  const chunks = html.match(
    /self\.__next_f\.push\([\s\S]*?\)\s*(?:<\/script>)?/g,
  );

  const text = chunks?.join("") ?? "";

  return Buffer.byteLength(text);
}

function claimBytes(html: string): number {
  const matches = html.match(
    /"(?:memberships|permissions|authz_ver)"\s*:\s*(?:\[[\s\S]*?\]|\{[\s\S]*?\}|-?\d+)/g,
  );

  return Buffer.byteLength(matches?.join("") ?? "");
}

function wavesOf(response: Response | null): number | null {
  const header = response?.headers()["x-bsb-stats"];

  if (!header) {
    return null;
  }

  const waves = Number(header.split(";")[1]);

  return Number.isFinite(waves) ? waves : null;
}

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

async function record(page: Page, route: string): Promise<void> {
  const document = page.waitForResponse(
    (response) =>
      response.request().resourceType() === "document" &&
      response.url().includes(route),
  );

  await page.goto(route);
  const response = await document.catch(() => null);
  const html = await page.content();

  expect(html.length).toBeGreaterThan(0);

  test
    .info()
    .annotations.push({
      type: "scale-payload",
      description: JSON.stringify({
        route,
        htmlBytes: Buffer.byteLength(html),
        flightBytes: flightBytes(html),
        claimBytes: claimBytes(html),
        waves: wavesOf(response),
      }),
    });
}

test("records the payload of the dashboard", async ({ page }) => {
  await record(page, "/");
});

test("records the payload of the customers list", async ({ page }) => {
  await record(page, "/customers");
});

test("records the payload of a customer", async ({ page }) => {
  await record(page, "/customers/00000000-0000-4000-8000-00000000a001");
});
