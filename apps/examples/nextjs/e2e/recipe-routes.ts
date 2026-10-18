/**
 * Where each UI recipe renders, shared by `recipes.spec.ts` (the region
 * renders) and `recipe-screenshots.spec.ts` (the marketing screenshots).
 * Recipes that need a record create it through the UI first, so both run
 * against a freshly reset stack.
 */
import { expect, type Locator, type Page } from "@playwright/test";

export interface RecipeRoute {
  readonly slug: string;
  readonly path: string;
  /** Opens a dialog or menu, creates a record, or follows a link first. */
  readonly prepare?: (page: Page) => Promise<void>;
  /** The region when it isn't `[data-recipe="<slug>"]`. */
  readonly region?: (page: Page) => Locator;
}

const unique = (): string => Date.now().toString(36);

export const openCustomer = async (page: Page): Promise<void> => {
  await page.getByRole("link", { name: "Road Runner Inc" }).click();
  await page.waitForURL((url) => url.pathname.startsWith("/en/customers/"));
};

const submitDialog = async (page: Page, name: string): Promise<void> => {
  await page
    .getByRole("dialog")
    .getByRole("button", { name, exact: true })
    .click();
};

const createContact = async (page: Page): Promise<void> => {
  await page.getByRole("button", { name: "Add contact" }).first().click();
  await page.getByRole("dialog").getByLabel("Name").fill("Acme Rockets");
  await submitDialog(page, "Add");
  await page.waitForURL((url) => url.pathname.startsWith("/en/crm/contacts/"));
};

const createDraftOrder = async (page: Page): Promise<void> => {
  await page.getByRole("button", { name: "New product" }).click();
  const product = page.getByRole("dialog");
  await product.getByLabel("Name").fill(`Linen shirt ${unique()}`);
  await product.getByLabel("SKU").fill(`SHIRT-${unique()}`);
  await product.getByLabel(/^Price/).fill("49.00");
  await submitDialog(page, "Create product");
  await expect(product).toBeHidden();

  await page.goto("/en/shop/orders");
  await page.getByRole("button", { name: "New draft order" }).click();
  await submitDialog(page, "Add to draft");
  await page.waitForURL((url) => url.pathname.startsWith("/en/shop/orders/"));
};

/** Sets up the organization's booking page once, then finds its link button. */
const setUpBookingPage = async (page: Page): Promise<void> => {
  const newLink = page.getByRole("button", { name: "New link" });
  const setUp = page.getByRole("button", { name: "Set up booking page" });
  await expect(newLink.or(setUp).first()).toBeVisible();

  if (await setUp.isVisible()) {
    await setUp.click();
  }

  await expect(newLink).toBeVisible();
};

/** Creates a folder in the drive and opens its actions menu. */
const openFolderMenu = async (page: Page): Promise<void> => {
  const name = `Contracts ${unique()}`;
  await page.getByRole("button", { name: "New folder" }).click();
  await page.getByRole("dialog").getByLabel("Name").fill(name);
  await submitDialog(page, "Create");
  await page.getByRole("button", { name: `Actions for ${name}` }).click();
};

export const RECIPE_ROUTES: readonly RecipeRoute[] = [
  { slug: "profile-form", path: "/en/settings/profile" },
  { slug: "mfa-setup", path: "/en/settings/security" },
  { slug: "sessions-list", path: "/en/settings/security" },
  { slug: "workspace-url-field", path: "/en/settings/organization" },
  { slug: "feature-flag-toggles", path: "/en/settings/organization" },
  { slug: "sso-settings", path: "/en/settings/sso" },
  { slug: "access-requests-inbox", path: "/en/settings/access-requests" },
  { slug: "custom-fields-editor", path: "/en/settings/custom-fields" },
  { slug: "invoices-table", path: "/en/settings/billing" },
  { slug: "service-principals-table", path: "/en/settings/api-keys" },
  { slug: "webhook-endpoints", path: "/en/settings/webhooks" },
  { slug: "signing-keys-rotation", path: "/en/settings/signing-keys" },
  { slug: "job-runs-table", path: "/en/settings/jobs" },
  { slug: "data-export-delete", path: "/en/settings/privacy" },
  { slug: "ai-provider-settings", path: "/en/settings/ai-providers" },
  { slug: "push-opt-in", path: "/en/settings/preferences" },
  { slug: "waitlist-signup", path: "/en/waitlist" },
  { slug: "inbox-threads", path: "/en/inbox" },
  { slug: "ai-task-queue", path: "/en/assistant/tasks" },
  { slug: "chat-with-history", path: "/en/assistant" },
  { slug: "agent-run-trace", path: "/en/assistant/activity" },
  { slug: "knowledge-upload", path: "/en/knowledge" },
  { slug: "workflow-runs", path: "/en/workflows" },
  { slug: "metrics-dashboard", path: "/en/metrics" },
  { slug: "reactions-bar", path: "/en/customers", prepare: openCustomer },
  { slug: "share-link-dialog", path: "/en/customers", prepare: openCustomer },
  {
    slug: "attachments-uploader",
    path: "/en/customers",
    prepare: openCustomer,
  },
  { slug: "sla-badges", path: "/en/customers", prepare: openCustomer },
  { slug: "related-items-panel", path: "/en/customers", prepare: openCustomer },
  { slug: "version-history", path: "/en/customers", prepare: openCustomer },
  { slug: "contact-detail", path: "/en/crm/contacts", prepare: createContact },
  {
    slug: "activity-timeline",
    path: "/en/crm/contacts",
    prepare: createContact,
  },
  { slug: "deal-board", path: "/en/crm/deals" },
  { slug: "targets-progress", path: "/en/crm/deals" },
  {
    slug: "quote-builder",
    path: "/en/crm/quotes",
    prepare: async (page) => {
      await page.getByRole("button", { name: "New quote" }).first().click();
      await page.getByRole("dialog").getByLabel("Title").fill("Annual plan");
      await submitDialog(page, "Create");
      await page.waitForURL((url) =>
        url.pathname.startsWith("/en/crm/quotes/"),
      );
    },
  },
  { slug: "work-item-board", path: "/en/work" },
  { slug: "team-picker", path: "/en/work" },
  { slug: "work-item-grid", path: "/en/work/grid" },
  {
    slug: "bulk-action-bar",
    path: "/en/work",
    prepare: async (page) => {
      await page.getByRole("button", { name: "New item" }).click();
      await page
        .getByRole("dialog")
        .getByLabel("Title")
        .fill("Ship the launch post");
      await submitDialog(page, "Create item");
      await expect(page.getByRole("dialog")).toBeHidden();
      await page.goto("/en/work/grid");
      await page.getByRole("checkbox", { name: "Select all" }).click();
    },
  },
  { slug: "approvals-queue", path: "/en/approvals" },
  { slug: "employee-directory", path: "/en/people" },
  { slug: "hiring-board", path: "/en/people/hiring" },
  { slug: "timesheet", path: "/en/people/time" },
  { slug: "calendar-view", path: "/en/calendar" },
  { slug: "reminders-list", path: "/en/calendar" },
  {
    slug: "availability-editor",
    path: "/en/calendar/availability",
    prepare: setUpBookingPage,
  },
  {
    slug: "booking-page",
    path: "/en/calendar/availability",
    prepare: async (page) => {
      await setUpBookingPage(page);
      await page.getByRole("button", { name: "New link" }).click();
      const link = page.getByRole("dialog").getByLabel("Link", { exact: true });
      await expect(link).not.toHaveValue("");
      await page.goto(await link.inputValue());
    },
  },
  { slug: "product-catalog-grid", path: "/en/shop" },
  { slug: "inventory-table", path: "/en/shop/inventory" },
  { slug: "order-detail", path: "/en/shop", prepare: createDraftOrder },
  { slug: "promotion-code-field", path: "/en/shop", prepare: createDraftOrder },
  { slug: "drive-explorer", path: "/en/drive" },
  {
    slug: "grants-editor",
    path: "/en/drive",
    prepare: async (page) => {
      await openFolderMenu(page);
      await page.getByRole("menuitem", { name: "Share" }).click();
    },
  },
  {
    slug: "undo-toast",
    path: "/en/drive",
    prepare: async (page) => {
      await openFolderMenu(page);
      await page.getByRole("menuitem", { name: "Move to trash" }).click();
    },
    region: (page) =>
      page
        .locator("[data-sonner-toast]")
        .filter({ has: page.locator('[data-recipe="undo-toast"]') }),
  },
  { slug: "trash-bin", path: "/en/trash" },
  {
    slug: "form-builder",
    path: "/en/forms",
    prepare: async (page) => {
      await page.getByRole("button", { name: "New form" }).first().click();
      await page
        .getByRole("dialog")
        .getByLabel("Title")
        .fill("Customer feedback");
      await submitDialog(page, "Create");
      await page.waitForURL((url) => url.pathname.startsWith("/en/forms/"));
    },
  },
  { slug: "csv-import-wizard", path: "/en/imports" },
  { slug: "templates-gallery", path: "/en/templates" },
  {
    slug: "document-editor",
    path: "/en/documents",
    prepare: async (page) => {
      await page
        .getByRole("link", { name: "Notes for Road Runner Inc" })
        .click();
      await page.waitForURL((url) => url.pathname.startsWith("/en/documents/"));
    },
  },
];
