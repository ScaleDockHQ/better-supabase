import { expect, type Locator, type Page, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import {
  cardTitle,
  clickSettingsTab,
  heading,
  settingsTab,
  signIn,
  visibleTestId,
  visibleText,
} from "./nav";
import { type UserName, users } from "./users";

interface Tab {
  readonly path: string;
  readonly label: string;
  /** Content that only renders once the tab's data has loaded. */
  readonly content: (page: Page, user: UserName) => readonly Locator[];
  /** Users who see the tab; the others must not. */
  readonly visibleTo: readonly UserName[];
}

const everyone: readonly UserName[] = ["admin", "member", "globex"];

/** In the order of the settings navigation, ending back on Profile. */
const tabs: readonly Tab[] = [
  {
    path: "/settings/security",
    label: "Security",
    content: (page) => [
      visibleTestId(page, "mfa-status"),
      visibleText(page, "No agents are connected."),
    ],
    visibleTo: everyone,
  },
  {
    path: "/settings/organization",
    label: "Organization",
    content: (page) => [cardTitle(page, "General")],
    visibleTo: everyone,
  },
  {
    path: "/settings/members",
    label: "Members",
    content: (page) => [cardTitle(page, "Members")],
    visibleTo: everyone,
  },
  {
    path: "/settings/billing",
    label: "Billing",
    content: (page) => [visibleTestId(page, "current-plan")],
    visibleTo: everyone,
  },
  {
    path: "/settings/api-keys",
    label: "API keys",
    content: (page) => [cardTitle(page, "API keys")],
    visibleTo: everyone,
  },
  {
    path: "/settings/audit",
    label: "Audit log",
    // Acme is on Pro; Globex, on the free plan, gets the upsell.
    content: (page, user) => [
      user === "globex"
        ? visibleTestId(page, "audit-upsell")
        : cardTitle(page, "Audit log"),
    ],
    visibleTo: ["admin", "globex"],
  },
  {
    path: "/settings/profile",
    label: "Profile",
    content: (page) => [visibleTestId(page, "profile-role")],
    visibleTo: everyone,
  },
];

for (const name of Object.keys(users) as UserName[]) {
  test.describe(name, () => {
    test("every settings tab commits its content on a click from another tab", async ({
      page,
    }) => {
      // A fresh session: the Security tab asks the Auth server, which refuses
      // a saved token once the sign-out flow has ended the user's sessions.
      await signIn(page, users[name].email);
      await page.goto("/en/settings/profile");
      await expect(visibleTestId(page, "profile-role")).toBeVisible();
      for (const tab of tabs) {
        if (!tab.visibleTo.includes(name)) {
          await expect(settingsTab(page, tab.label)).toHaveCount(0);
          continue;
        }
        await expectInstant(page, {
          during: clickSettingsTab(page, tab.label, `/en${tab.path}`),
          visible: [heading(page, "Settings"), ...tab.content(page, name)],
        });
      }
    });
  });
}
