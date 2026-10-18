/**
 * Screenshots of the UI recipes for bettersupabase.com/recipes, written to
 * `apps/marketing/public/recipes/<slug>.png`. It runs on demand with
 * `pnpm screenshots:recipes` against the local stack, never in CI, so it
 * skips unless `RECIPE_SCREENSHOTS=1`. Run `pnpm recipes` afterwards so
 * `recipes.json` picks up the new files and their sizes.
 *
 * Each region is the element with `data-recipe="<slug>"`, set where the
 * example renders the recipe's component. Dialogs and menus render in a
 * portal, so those recipes open them and capture the popup instead.
 */
import { expect, type Locator, type Page, test } from "@playwright/test";
import { join } from "node:path";

import { users } from "./users";

const OUT = join(import.meta.dirname, "../../../marketing/public/recipes");

interface Shot {
  readonly slug: string;
  readonly path: string;
  /** Opens a dialog or menu, or follows a link, before the capture. */
  readonly prepare?: (page: Page) => Promise<void>;
  /** The region when it isn't `[data-recipe="<slug>"]`. */
  readonly region?: (page: Page) => Locator;
}

const openCustomer = async (page: Page): Promise<void> => {
  await page.getByRole("link", { name: "Road Runner Inc" }).click();
  await page.waitForURL((url) => url.pathname.startsWith("/en/customers/"));
};

const SHOTS: readonly Shot[] = [
  { slug: "notification-bell", path: "/en" },
  { slug: "notification-list", path: "/en/notifications" },
  {
    slug: "command-search",
    path: "/en",
    prepare: async (page) => {
      await page.getByRole("button", { name: "Search", exact: true }).click();
      await page
        .getByRole("searchbox", { name: "Search customers" })
        .fill("road");
      await expect(
        page.getByRole("dialog").getByRole("link").first(),
      ).toBeVisible();
    },
    region: (page) => page.getByRole("dialog"),
  },
  {
    slug: "onboarding-checklist",
    path: "/en",
    region: (page) => page.getByTestId("onboarding"),
  },
  {
    slug: "usage-meter",
    path: "/en",
    region: (page) => page.getByTestId("usage"),
  },
  { slug: "comment-thread", path: "/en/customers", prepare: openCustomer },
  { slug: "tag-input", path: "/en/customers", prepare: openCustomer },
  {
    slug: "org-switcher",
    path: "/en",
    prepare: async (page) => {
      await page.getByRole("button", { name: "Switch organization" }).click();
    },
    region: (page) => page.getByRole("menu"),
  },
  { slug: "plan-picker", path: "/en/settings/billing" },
  { slug: "feature-gate", path: "/en/settings/audit" },
  { slug: "audit-log-table", path: "/en/settings/audit" },
  {
    slug: "settings-layout",
    path: "/en/settings/preferences",
    region: (page) => page.getByTestId("settings-layout"),
  },
  { slug: "members-table", path: "/en/settings/members" },
  {
    slug: "invite-dialog",
    path: "/en/settings/members",
    prepare: async (page) => {
      await page.getByRole("button", { name: "Invite", exact: true }).click();
    },
    region: (page) => page.getByRole("dialog"),
  },
  { slug: "api-keys-table", path: "/en/settings/api-keys" },
];

test.describe("recipe screenshots", () => {
  // oxlint-disable-next-line playwright/no-skipped-test -- an on-demand run that writes into apps/marketing; `pnpm screenshots:recipes` sets the variable
  test.skip(
    // oxlint-disable-next-line turbo/no-undeclared-env-vars -- set by `pnpm screenshots:recipes`, which runs outside Turbo
    process.env["RECIPE_SCREENSHOTS"] !== "1",
    "Runs with pnpm screenshots:recipes",
  );

  test.use({
    storageState: users.admin.storageState,
    viewport: { width: 1024, height: 768 },
    deviceScaleFactor: 2,
    colorScheme: "light",
    reducedMotion: "reduce",
  });

  for (const shot of SHOTS) {
    test(shot.slug, async ({ page }) => {
      await page.goto(shot.path);
      await shot.prepare?.(page);

      const region =
        shot.region?.(page) ??
        page.locator(`[data-recipe="${shot.slug}"]`).filter({ visible: true });

      await expect(region).toBeVisible();
      await expect(region.locator('[aria-busy="true"]')).toHaveCount(0);
      await region.screenshot({
        path: join(OUT, `${shot.slug}.png`),
        animations: "disabled",
      });
    });
  }
});
