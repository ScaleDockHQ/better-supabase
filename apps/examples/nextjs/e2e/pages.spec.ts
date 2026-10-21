import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import type { Locale } from "./nav";
import type { UserName } from "./users";

import { clickSidebar, heading, sidebarLink, visibleTestId } from "./nav";
import { users } from "./users";

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
    path: "/work",
    label: { en: "Work", nl: "Werk" },
    heading: { en: "Work", nl: "Werk" },
    visibleTo: everyone,
  },
  {
    path: "/work/grid",
    label: { en: "Work grid", nl: "Werkraster" },
    heading: { en: "Work grid", nl: "Werkraster" },
    visibleTo: everyone,
  },
  {
    path: "/approvals",
    label: { en: "Approvals", nl: "Goedkeuringen" },
    heading: { en: "Approvals", nl: "Goedkeuringen" },
    visibleTo: everyone,
  },
  {
    path: "/people",
    label: { en: "People", nl: "Mensen" },
    heading: { en: "People", nl: "Mensen" },
    visibleTo: everyone,
  },
  {
    path: "/people/hiring",
    label: { en: "Hiring", nl: "Werving" },
    heading: { en: "Hiring", nl: "Werving" },
    visibleTo: everyone,
  },
  {
    path: "/people/time",
    label: { en: "Time", nl: "Tijd" },
    heading: { en: "Time", nl: "Tijd" },
    visibleTo: everyone,
  },
  {
    path: "/calendar",
    label: { en: "Calendar", nl: "Agenda" },
    heading: { en: "Calendar", nl: "Agenda" },
    visibleTo: everyone,
  },
  {
    path: "/calendar/availability",
    label: { en: "Availability", nl: "Beschikbaarheid" },
    heading: { en: "Availability", nl: "Beschikbaarheid" },
    visibleTo: ["admin", "globex"],
  },
  {
    path: "/crm/contacts",
    label: { en: "Contacts", nl: "Contacten" },
    heading: { en: "Contacts", nl: "Contacten" },
    visibleTo: everyone,
  },
  {
    path: "/crm/deals",
    label: { en: "Deals", nl: "Deals" },
    heading: { en: "Deals", nl: "Deals" },
    visibleTo: everyone,
  },
  {
    path: "/crm/quotes",
    label: { en: "Quotes", nl: "Offertes" },
    heading: { en: "Quotes", nl: "Offertes" },
    visibleTo: everyone,
  },
  {
    path: "/shop",
    label: { en: "Shop", nl: "Winkel" },
    heading: { en: "Shop", nl: "Winkel" },
    visibleTo: everyone,
  },
  {
    path: "/shop/inventory",
    label: { en: "Inventory", nl: "Voorraad" },
    heading: { en: "Inventory", nl: "Voorraad" },
    visibleTo: everyone,
  },
  {
    path: "/shop/orders",
    label: { en: "Orders", nl: "Bestellingen" },
    heading: { en: "Orders", nl: "Bestellingen" },
    visibleTo: everyone,
  },
  {
    path: "/drive",
    label: { en: "Drive", nl: "Drive" },
    heading: { en: "Drive", nl: "Drive" },
    visibleTo: everyone,
  },
  {
    path: "/documents",
    label: { en: "Documents", nl: "Documenten" },
    heading: { en: "Documents", nl: "Documenten" },
    visibleTo: everyone,
  },
  {
    path: "/forms",
    label: { en: "Forms", nl: "Formulieren" },
    heading: { en: "Forms", nl: "Formulieren" },
    visibleTo: everyone,
  },
  {
    path: "/templates",
    label: { en: "Templates", nl: "Sjablonen" },
    heading: { en: "Templates", nl: "Sjablonen" },
    visibleTo: everyone,
  },
  {
    path: "/imports",
    label: { en: "Imports", nl: "Imports" },
    heading: { en: "Imports", nl: "Imports" },
    visibleTo: ["admin", "globex"],
  },
  {
    path: "/trash",
    label: { en: "Trash", nl: "Prullenbak" },
    heading: { en: "Trash", nl: "Prullenbak" },
    visibleTo: everyone,
  },
  {
    path: "/metrics",
    label: { en: "Metrics", nl: "Statistieken" },
    heading: { en: "Metrics", nl: "Statistieken" },
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
    path: "/assistant/tasks",
    label: { en: "AI tasks", nl: "AI-taken" },
    heading: { en: "AI tasks", nl: "AI-taken" },
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
    path: "/settings/ai-providers",
    label: { en: "AI providers", nl: "AI-providers" },
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

      if (name === "member") {
        test("a page behind a permission redirects to the dashboard", async ({
          page,
        }) => {
          await page.goto(`/${locale}/settings/audit`);
          await expect(page).toHaveURL((url) => url.pathname === `/${locale}`);
        });
      }

      if (name === "globex") {
        test("a page behind a flag that is off is a 404", async ({ page }) => {
          await page.goto(`/${locale}/beta`);
          await expect(
            page.getByText(
              locale === "en" ? "Page not found" : "Pagina niet gevonden",
            ),
          ).toBeVisible();
        });
      }
    });
  }
}
