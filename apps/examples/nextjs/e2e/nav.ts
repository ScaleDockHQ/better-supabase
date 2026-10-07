import type { Locator, Page } from "@playwright/test";

/** A link in the sidebar, the real `<Link>` a user clicks. */
export function sidebarLink(page: Page, label: string): Locator {
  return page
    .getByRole("navigation", { name: "Main" })
    .getByRole("link", { name: label, exact: true });
}

export function heading(page: Page, name: string): Locator {
  return page.getByRole("heading", { level: 1, name });
}
