import { expect, type Locator, type Page } from "@playwright/test";

import { password } from "./users";

export type Locale = "en" | "nl";

/** A link in the sidebar, the real `<Link>` a user clicks. */
export function sidebarLink(page: Page, label: string): Locator {
  return page
    .getByRole("navigation", { name: /^(Main|Hoofdmenu)$/ })
    .getByRole("link", { name: label, exact: true });
}

export function heading(page: Page, name: string): Locator {
  return page.getByRole("heading", { level: 1, name, exact: true });
}

/** Clicks a sidebar link and waits for the URL: the navigation `expectInstant` holds. */
export function clickSidebar(
  page: Page,
  label: string,
  pathname: string,
): () => Promise<void> {
  return async () => {
    await sidebarLink(page, label).click();
    await page.waitForURL((url) => url.pathname === pathname);
  };
}

/** Signs in through the real form and waits for `landing`, the dashboard by default. */
export async function signIn(
  page: Page,
  email: string,
  locale: Locale = "en",
  landing: string = `/${locale}`,
): Promise<void> {
  await page.goto(`/${locale}/login`);
  await field(page, locale === "en" ? "Email" : "E-mail").fill(email);
  await field(page, locale === "en" ? "Password" : "Wachtwoord").fill(password);
  await page
    .getByRole("button", { name: locale === "en" ? "Sign in" : "Inloggen" })
    .click();
  await page.waitForURL((url) => url.pathname === landing);
  if (landing === `/${locale}`)
    await expect(heading(page, "Dashboard")).toBeVisible();
}

export async function openAccountMenu(page: Page): Promise<void> {
  await page
    .getByRole("button", { name: /^(Account menu|Accountmenu)$/ })
    .click();
}

/**
 * A test id on the visible page. Cache Components keeps routes you left in a
 * hidden `<Activity>`, so the same id can also exist in a hidden copy.
 */
export function visibleTestId(page: Page, id: string): Locator {
  return page.getByTestId(id).filter({ visible: true });
}

/**
 * Text on the visible page. Besides hidden routes, a streamed Suspense
 * boundary sits in a hidden `<div>` for a moment before React swaps it in.
 */
export function visibleText(page: Page, text: string | RegExp): Locator {
  return page.getByText(text, { exact: true }).filter({ visible: true });
}

/** A form field by its label on the visible page, for the same reason as `visibleTestId`. */
export function field(page: Page, label: string): Locator {
  return page.getByLabel(label, { exact: true }).filter({ visible: true });
}

/**
 * Picks a radio item in an account-menu submenu with the keyboard. A click on
 * the sub-trigger toggles the submenu shut, and a pointer path to the item
 * can cross another sub-trigger and open that one instead.
 */
export async function pickInSubmenu(
  page: Page,
  submenu: string,
  item: string,
): Promise<void> {
  await openAccountMenu(page);
  await page.getByRole("menuitem", { name: submenu }).press("ArrowRight");
  await page.getByRole("menuitemradio", { name: item }).press("Enter");
}
