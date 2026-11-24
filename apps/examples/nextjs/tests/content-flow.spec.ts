/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import { signIn } from "./support/example-session";

// The content story of the seed: a live post, a scheduled page and a draft.
// Every entry point is locked instant; the figures and sections stream in
// behind the frame.

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("the content hub shows its KPI band and the seeded entries", async ({
  page,
}) => {
  await page.goto("/content");

  const main = page.getByRole("main");

  await expect(
    main.getByTestId("kpi-band").filter({ visible: true }),
  ).toBeVisible();
  await expect(
    main.getByText("Spring launch notes").filter({ visible: true }),
  ).toBeVisible();
  await expect(
    main.getByText("Summer roadmap").filter({ visible: true }),
  ).toBeVisible();
});

test("an entry opens with its status and its record sections", async ({
  page,
}) => {
  await page.goto("/content");

  const link = page
    .getByRole("main")
    .getByRole("link", { name: "Summer roadmap" });

  await expect(link).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) => url.pathname.startsWith("/content/"));
    },
    visible: [page.getByRole("link", { name: "All content" })],
  });

  const main = page.getByRole("main");

  await expect(
    main.getByRole("heading", { name: "Summer roadmap" }),
  ).toBeVisible();
  await expect(main.getByText("Draft").first()).toBeVisible();
  await expect(
    main.getByRole("button", { name: "Publish with version" }),
  ).toBeVisible();
});

test("a draft is published with a version from its page", async ({ page }) => {
  const slug = `launch-${Date.now()}`;

  await page.goto("/content");
  await page.getByRole("button", { name: "New entry" }).click();
  await page.getByLabel("Title").fill(`Launch ${slug}`);
  await page.getByLabel("Slug").fill(slug);
  await page.getByRole("button", { name: "Save draft" }).click();

  await page
    .getByRole("main")
    .getByRole("link", { name: `Launch ${slug}` })
    .click();
  await page.getByRole("button", { name: "Publish with version" }).click();
  await page.getByLabel("Version label (optional)").fill("First cut");
  await page.getByRole("button", { name: "Publish", exact: true }).click();

  await expect(
    page
      .getByRole("main")
      .getByText("Published")
      .filter({ visible: true })
      .first(),
  ).toBeVisible();
});
