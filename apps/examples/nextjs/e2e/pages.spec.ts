import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import {
  clickSidebar,
  heading,
  type Locale,
  sidebarLink,
  visibleTestId,
} from "./nav";
import { type UserName, users } from "./users";

interface Route {
  readonly path: string;
  readonly label: Record<Locale, string>;
  readonly heading: Record<Locale, string>;
  /** Users who see the menu entry; the others must not. */
  readonly visibleTo: readonly UserName[];
}

const everyone: readonly UserName[] = ["admin", "member", "globex"];
const settings = { en: "Settings", nl: "Instellingen" };

const routes: readonly Route[] = [
  {
    path: "/customers",
    label: { en: "Customers", nl: "Klanten" },
    heading: { en: "Customers", nl: "Klanten" },
    visibleTo: everyone,
  },
  {
    path: "/notifications",
    label: { en: "Notifications", nl: "Meldingen" },
    heading: { en: "Notifications", nl: "Meldingen" },
    visibleTo: everyone,
  },
  {
    path: "/workflows",
    label: { en: "Workflows", nl: "Workflows" },
    heading: { en: "Workflows", nl: "Workflows" },
    visibleTo: everyone,
  },
  {
    path: "/workflows/builder",
    label: { en: "Workflow builder", nl: "Workflowbouwer" },
    heading: { en: "Workflow builder", nl: "Workflowbouwer" },
    visibleTo: everyone,
  },
  {
    path: "/inbox",
    label: { en: "Inbox", nl: "Inbox" },
    heading: { en: "Inbox", nl: "Inbox" },
    visibleTo: everyone,
  },
  {
    path: "/assistant",
    label: { en: "Assistant", nl: "Assistent" },
    heading: { en: "Assistant", nl: "Assistent" },
    visibleTo: everyone,
  },
  {
    // The `beta-page` flag is on for Acme only.
    path: "/beta",
    label: { en: "Beta", nl: "Bèta" },
    heading: { en: "Beta", nl: "Bèta" },
    visibleTo: ["admin", "member"],
  },
  {
    path: "/settings/members",
    label: { en: "Members", nl: "Leden" },
    heading: settings,
    visibleTo: everyone,
  },
  {
    path: "/settings/billing",
    label: { en: "Billing", nl: "Facturatie" },
    heading: settings,
    visibleTo: everyone,
  },
  {
    path: "/settings/api-keys",
    label: { en: "API keys", nl: "API-sleutels" },
    heading: settings,
    visibleTo: everyone,
  },
  {
    path: "/settings/audit",
    label: { en: "Audit log", nl: "Auditlog" },
    heading: settings,
    visibleTo: ["admin", "globex"],
  },
  {
    path: "/settings/organization",
    label: { en: "Settings", nl: "Instellingen" },
    heading: settings,
    visibleTo: everyone,
  },
];

for (const name of Object.keys(users) as UserName[]) {
  for (const locale of ["en", "nl"] as const) {
    test.describe(`${name} in ${locale}`, () => {
      test.use({ storageState: users[name].storageState });

      test("every menu page commits its shell on a click", async ({ page }) => {
        await page.goto(`/${locale}`);
        await expect(page.locator("html")).toHaveAttribute("lang", locale);
        await expect(visibleTestId(page, "organization-name")).toHaveText(
          users[name].organization,
        );
        for (const route of routes) {
          const link = sidebarLink(page, route.label[locale]);
          if (!route.visibleTo.includes(name)) {
            await expect(link).toHaveCount(0);
            continue;
          }
          await expectInstant(page, {
            during: clickSidebar(
              page,
              route.label[locale],
              `/${locale}${route.path}`,
            ),
            visible: [heading(page, route.heading[locale])],
          });
          await clickSidebar(page, "Dashboard", `/${locale}`)();
        }
      });

      if (name === "member")
        test("a page behind a permission redirects to the dashboard", async ({
          page,
        }) => {
          await page.goto(`/${locale}/settings/audit`);
          await expect(page).toHaveURL((url) => url.pathname === `/${locale}`);
        });

      if (name === "globex")
        test("a page behind a flag that is off is a 404", async ({ page }) => {
          await page.goto(`/${locale}/beta`);
          await expect(
            page.getByText(
              locale === "en" ? "Page not found" : "Pagina niet gevonden",
            ),
          ).toBeVisible();
        });
    });
  }
}
