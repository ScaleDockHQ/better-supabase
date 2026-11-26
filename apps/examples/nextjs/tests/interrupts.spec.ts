import { expect, test } from "@playwright/test";

// ADR 1252: notFound(), forbidden() and unauthorized() thrown inside
// "use cache: private" end the render, and a prefetch of the same page never
// shows the guarded content. The fixture is src/app/[locale]/(public)/status/probe.
const KINDS = [
  { kind: "not-found", code: 404 },
  { kind: "forbidden", code: 403 },
  { kind: "unauthorized", code: 401 },
] as const;

test("the control page renders its content", async ({ page }) => {
  await page.goto("/status/probe/ok");
  await expect(page.getByTestId("probe").first()).toHaveText("allowed");
});

for (const { kind, code } of KINDS) {
  test(`${kind} renders the ${String(code)} fallback`, async ({ request }) => {
    const response = await request.get(`/status/probe/${kind}`);
    const html = await response.text();

    expect(html).toContain(`NEXT_HTTP_ERROR_FALLBACK;${String(code)}`);
    expect(html).not.toContain('data-testid="probe"');
  });

  test(`${kind} survives a prefetch and a client navigation`, async ({
    page,
  }) => {
    const errors: string[] = [];

    page.on("pageerror", (error) => errors.push(error.message));
    await page.goto("/status/probe/ok");
    await page.evaluate(
      (href) =>
        // SAFETY: the App Router exposes its router on window.next.
        (
          window as unknown as {
            next: { router: { prefetch(href: string): Promise<void> } };
          }
        ).next.router.prefetch(href),
      `/status/probe/${kind}`,
    );
    await page.waitForTimeout(500);
    await page.evaluate((href) => {
      (
        window as unknown as { next: { router: { push(href: string): void } } }
      ).next.router.push(href);
    }, `/status/probe/${kind}`);
    await page.waitForURL((url) => url.pathname.endsWith(kind));
    await expect(page.getByTestId("probe")).toHaveCount(0);
    await expect(
      page.locator('meta[name="robots"][content="noindex"]'),
    ).toHaveCount(1);
    expect(errors).toEqual([]);
  });
}
