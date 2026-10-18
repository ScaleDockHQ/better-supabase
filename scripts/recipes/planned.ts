import type { RecipeSource } from "./sources.ts";

/** Recipes without example code yet. Each names the block it waits for. */
export const PLANNED: readonly RecipeSource[] = [
  {
    slug: "sessions-list",
    title: "Sessions list",
    blocks: ["sessions"],
    kind: "component",
    description:
      "The caller's signed-in devices with the last activity and a button to end each session.",
    missing:
      "the sessions block in the example app's database, and a page that uses it",
  },
  {
    slug: "sso-settings",
    title: "SSO connection settings",
    blocks: ["sso"],
    kind: "screen",
    description:
      "The organization's SAML or OIDC connection with its domains and the role new members get.",
    missing:
      "the sso block in the example app's database, and a page that uses it",
  },
  {
    slug: "access-requests-inbox",
    title: "Access requests inbox",
    blocks: ["access-requests"],
    kind: "screen",
    description:
      "Requests for access to a resource, with approve and deny buttons for the owner.",
    missing:
      "the access-requests block in the example app's database, and a page that uses it",
  },
  {
    slug: "grants-editor",
    title: "Grants editor",
    blocks: ["grants"],
    kind: "component",
    description:
      "The grants on a resource, with a picker to share it with a member or team at a level.",
    missing:
      "the grants block in the example app's database, and a page that uses it",
  },
  {
    slug: "reactions-bar",
    title: "Reactions bar",
    blocks: ["reactions"],
    kind: "component",
    description:
      "Emoji reactions under a record with counts, which toggle the caller's own reaction.",
    missing:
      "the reactions block in the example app's database, and a page that uses it",
  },
  {
    slug: "share-link-dialog",
    title: "Share link dialog",
    blocks: ["share-links"],
    kind: "component",
    description:
      "A dialog that creates an expiring link to a record and revokes it.",
    missing:
      "the share-links block in the example app's database, and a page that uses it",
  },
  {
    slug: "attachments-uploader",
    title: "Attachments uploader",
    blocks: ["attachments"],
    kind: "component",
    description:
      "A drop zone that uploads files to a record and lists them with a download link.",
    missing:
      "the attachments block in the example app's database, and a page that uses it",
  },
  {
    slug: "waitlist-signup",
    title: "Waitlist signup",
    blocks: ["waitlist"],
    kind: "component",
    description:
      "An email form that joins the waitlist and shows the position in line.",
    missing:
      "the waitlist block in the example app's database, and a page that uses it",
  },
  {
    slug: "contact-detail",
    title: "Contact detail",
    blocks: ["parties"],
    kind: "screen",
    description:
      "A person or company with its details, related contacts and the latest activity.",
    missing:
      "the parties block in the example app's database, and a page that uses it",
  },
  {
    slug: "deal-board",
    title: "Deal board",
    blocks: ["deals", "pipelines"],
    kind: "screen",
    description:
      "Deals as cards in pipeline stage columns, moved by drag and drop.",
    missing:
      "the deals and pipelines blocks in the example app's database, and a page that uses them",
  },
  {
    slug: "activity-timeline",
    title: "Activity timeline",
    blocks: ["engagements"],
    kind: "component",
    description: "Calls, emails and meetings with a contact, newest first.",
    missing:
      "the engagements block in the example app's database, and a page that uses it",
  },
  {
    slug: "quote-builder",
    title: "Quote builder",
    blocks: ["quotes"],
    kind: "screen",
    description:
      "A quote with line items, discounts and totals in minor units, sent for acceptance.",
    missing:
      "the quotes block in the example app's database, and a page that uses it",
  },
  {
    slug: "targets-progress",
    title: "Targets progress",
    blocks: ["targets"],
    kind: "component",
    description:
      "Sales targets for the period with the progress toward each one.",
    missing:
      "the targets block in the example app's database, and a page that uses it",
  },
  {
    slug: "work-item-board",
    title: "Work item board",
    blocks: ["work-items", "state-machine", "rank"],
    kind: "screen",
    description:
      "Work items in state columns, ordered by rank and moved through allowed transitions.",
    missing:
      "the work-items, state-machine and rank blocks in the example app's database, and a page that uses them",
  },
  {
    slug: "work-item-grid",
    title: "Work item grid",
    blocks: ["work-items", "saved-views"],
    kind: "screen",
    description:
      "A data grid of work items with filters, sorting and saved views.",
    missing:
      "the work-items and saved-views blocks in the example app's database, and a page that uses them",
  },
  {
    slug: "approvals-queue",
    title: "Approvals queue",
    blocks: ["approvals"],
    kind: "screen",
    description:
      "Requests waiting for the caller's decision, with approve and reject buttons.",
    missing:
      "the approvals block in the example app's database, and a page that uses it",
  },
  {
    slug: "sla-badges",
    title: "SLA badges",
    blocks: ["sla"],
    kind: "component",
    description:
      "A badge on a record with the time left before its SLA is breached.",
    missing:
      "the sla block in the example app's database, and a page that uses it",
  },
  {
    slug: "custom-fields-editor",
    title: "Custom fields editor",
    blocks: ["custom-fields"],
    kind: "screen",
    description:
      "A settings page that adds, orders and removes the custom fields of a record type.",
    missing:
      "the custom-fields block in the example app's database, and a page that uses it",
  },
  {
    slug: "bulk-action-bar",
    title: "Bulk action bar",
    blocks: ["bulk"],
    kind: "component",
    description:
      "A bar over a selection of rows that runs an action on all of them and reports failures.",
    missing:
      "the bulk block in the example app's database, and a page that uses it",
  },
  {
    slug: "undo-toast",
    title: "Undo toast",
    blocks: ["trash"],
    kind: "component",
    description:
      "A toast after a delete with a button that restores the record from the trash.",
    missing:
      "the trash block in the example app's database, and a page that uses it",
  },
  {
    slug: "related-items-panel",
    title: "Related items panel",
    blocks: ["relations"],
    kind: "component",
    description:
      "The records linked to a record, with a picker to add or remove a link.",
    missing:
      "the relations block in the example app's database, and a page that uses it",
  },
  {
    slug: "employee-directory",
    title: "Employee directory",
    blocks: ["employees"],
    kind: "screen",
    description:
      "A searchable list of employees with an org chart of who reports to whom.",
    missing:
      "the employees block in the example app's database, and a page that uses it",
  },
  {
    slug: "hiring-board",
    title: "Hiring board",
    blocks: ["hiring"],
    kind: "screen",
    description:
      "Candidates for an opening as cards in interview stage columns.",
    missing:
      "the hiring block in the example app's database, and a page that uses it",
  },
  {
    slug: "timesheet",
    title: "Timesheet",
    blocks: ["time-tracking"],
    kind: "screen",
    description:
      "A week of time entries per project with a running timer and totals.",
    missing:
      "the time-tracking block in the example app's database, and a page that uses it",
  },
  {
    slug: "invoices-table",
    title: "Invoices table",
    blocks: ["invoices"],
    kind: "component",
    description:
      "The organization's invoices with their status, amount and a link to the PDF.",
    missing:
      "the invoices block in the example app's database, and a page that uses it",
  },
  {
    slug: "product-catalog-grid",
    title: "Product catalog grid",
    blocks: ["catalog"],
    kind: "screen",
    description:
      "Products in a grid with prices, variants and a filter by collection.",
    missing:
      "the catalog block in the example app's database, and a page that uses it",
  },
  {
    slug: "inventory-table",
    title: "Inventory table",
    blocks: ["inventory"],
    kind: "component",
    description:
      "Stock levels per product and location, with a form to adjust a count.",
    missing:
      "the inventory block in the example app's database, and a page that uses it",
  },
  {
    slug: "order-detail",
    title: "Order detail",
    blocks: ["orders"],
    kind: "screen",
    description:
      "An order with its lines, totals, payment state and fulfillment steps.",
    missing:
      "the orders block in the example app's database, and a page that uses it",
  },
  {
    slug: "promotion-code-field",
    title: "Promotion code field",
    blocks: ["promotions"],
    kind: "component",
    description:
      "A field that checks a promotion code and shows the discount it gives.",
    missing:
      "the promotions block in the example app's database, and a page that uses it",
  },
  {
    slug: "calendar-view",
    title: "Calendar view",
    blocks: ["calendar"],
    kind: "screen",
    description:
      "A month and week calendar of events with a dialog to add one.",
    missing:
      "the calendar block in the example app's database, and a page that uses it",
  },
  {
    slug: "booking-page",
    title: "Booking page",
    blocks: ["bookings"],
    kind: "screen",
    description:
      "A public page that shows open slots and books one without overlaps.",
    missing:
      "the bookings block in the example app's database, and a page that uses it",
  },
  {
    slug: "availability-editor",
    title: "Availability editor",
    blocks: ["bookings"],
    kind: "component",
    description:
      "Weekly working hours and date overrides that set which slots can be booked.",
    missing:
      "the bookings block in the example app's database, and a page that uses it",
  },
  {
    slug: "reminders-list",
    title: "Reminders list",
    blocks: ["reminders"],
    kind: "component",
    description:
      "Upcoming reminders on records with buttons to snooze or dismiss them.",
    missing:
      "the reminders block in the example app's database, and a page that uses it",
  },
  {
    slug: "drive-explorer",
    title: "Drive explorer",
    blocks: ["drive", "drive-files"],
    kind: "screen",
    description:
      "Folders and files with upload, rename, move and a breadcrumb trail.",
    missing:
      "the drive and drive-files blocks in the example app's database, and a page that uses them",
  },
  {
    slug: "version-history",
    title: "Version history",
    blocks: ["versions"],
    kind: "component",
    description:
      "The saved versions of a record with a diff and a button to restore one.",
    missing:
      "the versions block in the example app's database, and a page that uses it",
  },
  {
    slug: "trash-bin",
    title: "Trash bin",
    blocks: ["trash"],
    kind: "screen",
    description:
      "Deleted records with buttons to restore them or delete them for good.",
    missing:
      "the trash block in the example app's database, and a page that uses it",
  },
  {
    slug: "form-builder",
    title: "Form builder",
    blocks: ["forms"],
    kind: "screen",
    description:
      "An editor for form fields and a preview, with the responses in a table.",
    missing:
      "the forms block in the example app's database, and a page that uses it",
  },
  {
    slug: "csv-import-wizard",
    title: "CSV import wizard",
    blocks: ["imports"],
    kind: "screen",
    description:
      "A stepper that uploads a CSV, maps its columns, validates the rows and imports them.",
    missing:
      "the imports block in the example app's database, and a page that uses it",
  },
  {
    slug: "templates-gallery",
    title: "Templates gallery",
    blocks: ["templates"],
    kind: "screen",
    description:
      "Templates in a grid with a preview and a button to create a record from one.",
    missing:
      "the templates block in the example app's database, and a page that uses it",
  },
  {
    slug: "document-editor",
    title: "Document editor",
    blocks: ["documents"],
    kind: "screen",
    description:
      "A rich text editor for a document with autosave and collaborators.",
    missing:
      "the documents block in the example app's database, and a page that uses it",
  },
  {
    slug: "webhook-endpoints",
    title: "Webhook endpoints",
    blocks: ["webhooks-out"],
    kind: "screen",
    description:
      "The organization's webhook endpoints with their recent deliveries and a retry button.",
    missing:
      "the webhooks-out block in the example app's database, and a page that uses it",
  },
  {
    slug: "service-principals-table",
    title: "Service principals table",
    blocks: ["service-principals"],
    kind: "component",
    description:
      "Machine identities with their scopes, last use and a button to disable one.",
    missing:
      "the service-principals block in the example app's database, and a page that uses it",
  },
  {
    slug: "signing-keys-rotation",
    title: "Signing keys rotation",
    blocks: ["signing-keys"],
    kind: "component",
    description:
      "The active and previous signing keys with a button to rotate them.",
    missing:
      "the signing-keys block in the example app's database, and a page that uses it",
  },
  {
    slug: "data-export-delete",
    title: "Data export and delete",
    blocks: ["data-lifecycle"],
    kind: "screen",
    description:
      "Buttons to export the caller's data and to request account deletion, with the request status.",
    missing:
      "the data-lifecycle block in the example app's database, and a page that uses it",
  },
  {
    slug: "job-runs-table",
    title: "Job runs table",
    blocks: ["jobs"],
    kind: "component",
    description:
      "The latest background job runs with their status, attempts and error, and a button to retry a failed run.",
    missing:
      "a jobs read that the app can call: the block's run queries are granted to service_role only",
  },
  {
    slug: "team-picker",
    title: "Team picker",
    blocks: ["teams"],
    kind: "component",
    description:
      "A select of the caller's teams in the active organization, to scope a page or assign work.",
    missing:
      "the teams block's API in the example app, and seeded teams to pick from",
  },
];
