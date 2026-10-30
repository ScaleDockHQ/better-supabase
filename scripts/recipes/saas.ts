import type { RecipeSource } from "./types.ts";

import { WEB_APP } from "./types.ts";

/** Recipes for the record, commerce, people, content and admin blocks. */
export const SAAS_RECIPES: readonly RecipeSource[] = [
  {
    slug: "sessions-list",
    title: "Sessions list",
    blocks: ["sessions"],
    kind: "component",
    description:
      "The caller's signed-in devices with the last activity and a button to end each session.",
    web: {
      file: `${WEB_APP}/src/features/sessions/components/sessions-list.tsx`,
      components: ["alert-dialog", "badge", "button", "card"],
      glue: [],
    },
  },
  {
    slug: "sso-settings",
    title: "SSO connection settings",
    blocks: ["sso"],
    kind: "screen",
    description:
      "The organization's SAML or OIDC connection with its domains and the role new members get.",
    web: {
      file: `${WEB_APP}/src/features/sso/components/sso-settings.tsx`,
      components: ["alert", "badge", "button", "card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "access-requests-inbox",
    title: "Access requests inbox",
    blocks: ["access-requests"],
    kind: "screen",
    description:
      "Requests for access to a resource, with approve and deny buttons for the owner.",
    web: {
      file: `${WEB_APP}/src/features/access-requests/components/access-requests-inbox.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "empty",
        "skeleton",
        "table",
      ],
      glue: [],
    },
  },
  {
    slug: "grants-editor",
    title: "Grants editor",
    blocks: ["drive"],
    kind: "component",
    description:
      "The grants on a drive item, inherited ones included, with a picker to share it with a member or team at a role.",
    web: {
      file: `${WEB_APP}/src/features/drive/components/grants-editor.tsx`,
      components: ["badge", "button", "dialog", "field", "select", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "file-request-upload",
    title: "File request upload",
    blocks: ["drive", "share-links"],
    kind: "screen",
    description:
      "The public page of a file request link, where anyone with the link sends a file into a folder, with the link's password when it has one.",
    web: {
      file: `${WEB_APP}/src/features/drive/components/file-request-upload.tsx`,
      components: ["badge", "button", "card", "empty", "field", "input"],
      glue: [],
    },
  },
  {
    slug: "document-register",
    title: "Document register",
    blocks: ["drive"],
    kind: "component",
    description:
      "The organization's controlled documents in a data grid with their number, status, effective version and next review date, flagged when the review is due.",
    web: {
      file: `${WEB_APP}/src/features/drive/components/document-register.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "empty",
        "skeleton",
        "@reui/data-grid",
        "@reui/frame",
      ],
      glue: [],
    },
  },
  {
    slug: "reactions-bar",
    title: "Reactions bar",
    blocks: ["reactions"],
    kind: "component",
    description:
      "Emoji reactions under a record with counts, which toggle the caller's own reaction.",
    web: {
      file: `${WEB_APP}/src/features/customers/components/reactions-bar.tsx`,
      components: ["alert", "button", "card", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "share-link-dialog",
    title: "Share link dialog",
    blocks: ["share-links"],
    kind: "component",
    description:
      "A dialog that creates an expiring link to a record and revokes it.",
    web: {
      file: `${WEB_APP}/src/features/customers/components/share-link-dialog.tsx`,
      components: [
        "alert-dialog",
        "badge",
        "button",
        "card",
        "dialog",
        "empty",
        "field",
        "input",
        "select",
      ],
      glue: [],
    },
  },
  {
    slug: "attachments-uploader",
    title: "Attachments uploader",
    blocks: ["attachments"],
    kind: "component",
    description:
      "A drop zone that uploads files to a record and lists them with a download link.",
    web: {
      file: `${WEB_APP}/src/features/customers/components/attachments-uploader.tsx`,
      components: ["alert-dialog", "badge", "button", "card", "empty"],
      glue: [],
    },
  },
  {
    slug: "waitlist-signup",
    title: "Waitlist signup",
    blocks: ["waitlist"],
    kind: "component",
    description:
      "An email form that joins the waitlist and shows the position in line.",
    web: {
      file: `${WEB_APP}/src/features/waitlist/components/waitlist-signup.tsx`,
      components: ["badge", "button", "card", "field", "input"],
      glue: [],
    },
  },
  {
    slug: "contact-detail",
    title: "Contact detail",
    blocks: ["contacts"],
    kind: "screen",
    description:
      "A person or company with its details, related contacts and the latest activity.",
    web: {
      file: `${WEB_APP}/src/features/crm/components/contact-detail.tsx`,
      components: ["badge", "card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "deal-board",
    title: "Deal board",
    blocks: ["deals", "pipelines"],
    kind: "screen",
    description:
      "Deals as cards in pipeline stage columns, moved by drag and drop.",
    web: {
      file: `${WEB_APP}/src/features/crm/components/deal-board.tsx`,
      components: ["card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "sequence-builder",
    title: "Sequence builder",
    blocks: ["sequences"],
    kind: "screen",
    description:
      "Each sequence's email, wait and task steps in order, with its enrollment counts, an Add step dialog and an Activate or Pause button.",
    web: {
      file: `${WEB_APP}/src/features/sequences/components/sequence-builder.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "dialog",
        "empty",
        "field",
        "input",
        "select",
        "skeleton",
      ],
      glue: [],
    },
  },
  {
    slug: "activity-timeline",
    title: "Activity timeline",
    blocks: ["activities"],
    kind: "component",
    description: "Calls, emails and meetings with a contact, newest first.",
    web: {
      file: `${WEB_APP}/src/features/crm/components/activity-timeline.tsx`,
      components: ["badge", "card", "empty", "separator", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "quote-builder",
    title: "Quote builder",
    blocks: ["quotes"],
    kind: "screen",
    description:
      "A quote with line items, discounts and totals in minor units, sent for acceptance.",
    web: {
      file: `${WEB_APP}/src/features/crm/components/quote-builder.tsx`,
      components: ["card", "skeleton", "table"],
      glue: [],
    },
  },
  {
    slug: "targets-progress",
    title: "Targets progress",
    blocks: ["goals"],
    kind: "component",
    description:
      "Sales targets for the period with the progress toward each one.",
    web: {
      file: `${WEB_APP}/src/features/crm/components/targets-progress.tsx`,
      components: ["badge", "card", "empty", "progress", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "work-item-board",
    title: "Work item board",
    blocks: ["tasks", "state-machine", "rank"],
    kind: "screen",
    description:
      "Work items in state columns, ordered by rank and moved through allowed transitions.",
    web: {
      file: `${WEB_APP}/src/features/work/components/work-item-board.tsx`,
      components: ["badge", "card", "@reui/kanban"],
      glue: [],
    },
  },
  {
    slug: "entity-form",
    title: "Entity form",
    blocks: ["tasks", "custom-fields"],
    kind: "component",
    description:
      "A create dialog whose inputs come from `recordForm`: the entity's own fields and the organization's custom fields, validated together by `useRecordForm` before the Server Action runs.",
    hook: { name: "useRecordForm", entry: "better-supabase/react" },
    web: {
      file: `${WEB_APP}/src/features/work/components/create-work-item-dialog.tsx`,
      components: ["button", "checkbox", "dialog", "field", "input", "select"],
      glue: [],
    },
  },
  {
    slug: "work-item-grid",
    title: "Work item grid",
    blocks: ["tasks", "saved-views"],
    kind: "screen",
    description:
      "A data grid of work items with filters, sorting and saved views.",
    web: {
      file: `${WEB_APP}/src/features/work/components/work-item-grid.tsx`,
      components: [
        "badge",
        "button",
        "checkbox",
        "dialog",
        "field",
        "input",
        "select",
        "table",
      ],
      glue: [],
    },
  },
  {
    slug: "approvals-queue",
    title: "Approvals queue",
    blocks: ["approvals"],
    kind: "screen",
    description:
      "Requests waiting for the caller's decision, with approve and reject buttons.",
    web: {
      file: `${WEB_APP}/src/features/approvals/components/approvals-queue.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "empty",
        "skeleton",
        "table",
      ],
      glue: [],
    },
  },
  {
    slug: "my-work",
    title: "My work",
    blocks: ["subjects", "tasks", "approvals", "reminders", "comments"],
    kind: "screen",
    description:
      "What waits on the caller across the installed blocks, from `loadMyWork`: assigned work, approvals, due reminders, mentions and SLA warnings, each linked to its record.",
    web: {
      file: `${WEB_APP}/src/features/my-work/components/my-work-list.tsx`,
      components: ["alert", "badge", "button", "card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "subject-timeline",
    title: "Subject timeline",
    blocks: ["comments", "attachments", "versions"],
    kind: "component",
    description:
      "One record's comments, files and versions merged newest first, from `bsb.record(...).timeline`, skipping the bindings the caller can't read.",
    web: {
      file: `${WEB_APP}/src/features/customers/components/customer-timeline.tsx`,
      components: ["badge", "button", "card", "empty"],
      glue: [],
    },
  },
  {
    slug: "sla-badges",
    title: "SLA badges",
    blocks: ["sla"],
    kind: "component",
    description:
      "A badge on a record with the time left before its SLA is breached.",
    web: {
      file: `${WEB_APP}/src/features/customers/components/sla-badges.tsx`,
      components: ["badge", "button", "card", "empty"],
      glue: [],
    },
  },
  {
    slug: "custom-fields-editor",
    title: "Custom fields editor",
    blocks: ["custom-fields"],
    kind: "screen",
    description:
      "A settings page that adds, orders and removes the custom fields of a record type.",
    web: {
      file: `${WEB_APP}/src/features/custom-fields/components/custom-fields-editor.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "empty",
        "skeleton",
        "table",
      ],
      glue: [],
    },
  },
  {
    slug: "bulk-action-bar",
    title: "Bulk action bar",
    blocks: ["bulk"],
    kind: "component",
    description:
      "A bar over a selection of rows that runs an action on all of them and reports failures.",
    web: {
      file: `${WEB_APP}/src/features/work/components/bulk-action-bar.tsx`,
      components: ["alert", "alert-dialog", "button", "select"],
      glue: [],
    },
  },
  {
    slug: "undo-toast",
    title: "Undo toast",
    blocks: ["trash"],
    kind: "component",
    description:
      "A toast after a delete with a button that restores the record from the trash.",
    web: {
      file: `${WEB_APP}/src/features/trash/components/undo-toast.tsx`,
      components: ["sonner"],
      glue: [],
    },
  },
  {
    slug: "related-items-panel",
    title: "Related items panel",
    blocks: ["relations"],
    kind: "component",
    description:
      "The records linked to a record, with a picker to add or remove a link.",
    web: {
      file: `${WEB_APP}/src/features/customers/components/related-items-panel.tsx`,
      components: ["badge", "button", "card", "empty", "field", "select"],
      glue: [],
    },
  },
  {
    slug: "employee-directory",
    title: "Employee directory",
    blocks: ["employees"],
    kind: "screen",
    description:
      "A searchable list of employees with an org chart of who reports to whom.",
    web: {
      file: `${WEB_APP}/src/features/people/components/employee-directory.tsx`,
      components: ["card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "qualification-matrix",
    title: "Qualification matrix",
    blocks: ["qualifications"],
    kind: "component",
    description:
      "A table of the members who lack a required qualification, hold an expired one or will lose one soon.",
    web: {
      file: `${WEB_APP}/src/features/qualifications/components/qualification-matrix.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "empty",
        "skeleton",
        "table",
      ],
      glue: [],
    },
  },
  {
    slug: "my-qualifications",
    title: "My qualifications",
    blocks: ["qualifications"],
    kind: "component",
    description:
      "The signed-in member's certificates and licences with their expiry, and the required ones they still lack.",
    web: {
      file: `${WEB_APP}/src/features/qualifications/components/my-qualifications.tsx`,
      components: ["alert", "badge", "button", "card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "roster-board",
    title: "Roster board",
    blocks: ["shifts"],
    kind: "screen",
    description:
      "This week's shifts in a column per day, with their status and how many places are filled.",
    web: {
      file: `${WEB_APP}/src/features/shifts/components/roster-board.tsx`,
      components: ["alert", "badge", "button", "card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "hiring-board",
    title: "Hiring board",
    blocks: ["hiring"],
    kind: "screen",
    description:
      "Candidates for an opening as cards in interview stage columns.",
    web: {
      file: `${WEB_APP}/src/features/people/components/hiring-board.tsx`,
      components: ["badge", "button", "card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "timesheet",
    title: "Timesheet",
    blocks: ["time-tracking"],
    kind: "screen",
    description:
      "A week of time entries per project with a running timer and totals.",
    web: {
      file: `${WEB_APP}/src/features/people/components/timesheet.tsx`,
      components: ["badge", "button", "card", "empty", "skeleton", "table"],
      glue: [],
    },
  },
  {
    slug: "dispatch-board",
    title: "Dispatch board",
    blocks: ["dispatch"],
    kind: "screen",
    description:
      "A week of technicians by day with their scheduled work orders, and the backlog to schedule.",
    web: {
      file: `${WEB_APP}/src/features/field/components/dispatch-board.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "dialog",
        "empty",
        "field",
        "input",
        "skeleton",
        "table",
      ],
      glue: [],
    },
  },
  {
    slug: "technician-day",
    title: "Technician day",
    blocks: ["dispatch"],
    kind: "screen",
    description:
      "A technician's stops for the day in route order, each with the button that moves it on.",
    web: {
      file: `${WEB_APP}/src/features/field/components/technician-day.tsx`,
      components: ["alert", "badge", "button", "card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "shipment-tracking",
    title: "Shipment tracking",
    blocks: ["shipments"],
    kind: "screen",
    description:
      "Shipments with their status and the tracking timeline of the selected one, newest event first.",
    web: {
      file: `${WEB_APP}/src/features/field/components/shipment-tracking.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "dialog",
        "empty",
        "field",
        "input",
        "skeleton",
        "table",
      ],
      glue: [],
    },
  },
  {
    slug: "invoices-table",
    title: "Invoices table",
    blocks: ["invoices"],
    kind: "component",
    description:
      "The organization's invoices with their status, amount and a link to the PDF.",
    web: {
      file: `${WEB_APP}/src/features/billing/components/invoices-table.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "empty",
        "skeleton",
        "table",
      ],
      glue: [],
    },
  },
  {
    slug: "product-catalog-grid",
    title: "Product catalog grid",
    blocks: ["catalog"],
    kind: "screen",
    description:
      "Products in a grid with prices, variants and a filter by collection.",
    web: {
      file: `${WEB_APP}/src/features/shop/components/product-catalog-grid.tsx`,
      components: ["alert", "badge", "button", "card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "inventory-table",
    title: "Inventory table",
    blocks: ["inventory"],
    kind: "component",
    description:
      "Stock levels per product and location, with a form to adjust a count.",
    web: {
      file: `${WEB_APP}/src/features/shop/components/inventory-table.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "empty",
        "skeleton",
        "table",
      ],
      glue: [],
    },
  },
  {
    slug: "order-detail",
    title: "Order detail",
    blocks: ["orders"],
    kind: "screen",
    description:
      "An order with its lines, totals, payment state and fulfillment steps.",
    web: {
      file: `${WEB_APP}/src/features/shop/components/order-detail.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "empty",
        "skeleton",
        "table",
      ],
      glue: [],
    },
  },
  {
    slug: "kitchen-display",
    title: "Kitchen display",
    blocks: ["orders"],
    kind: "screen",
    description:
      "Open tickets per kitchen station, each line moved from queued to served, refreshed over Realtime.",
    web: {
      file: `${WEB_APP}/src/features/shop/components/kitchen-display.tsx`,
      components: ["alert", "badge", "button", "card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "order-state-board",
    title: "Order state board",
    blocks: ["orders"],
    kind: "component",
    description:
      "Today's kitchen orders in preparation-state columns; dragging an order forward moves all of its lines.",
    web: {
      file: `${WEB_APP}/src/features/shop/components/order-state-board.tsx`,
      components: ["badge", "card", "@reui/kanban"],
      glue: [],
    },
  },
  {
    slug: "promotion-code-field",
    title: "Promotion code field",
    blocks: ["promotions"],
    kind: "component",
    description:
      "A field that checks a promotion code and shows the discount it gives.",
    web: {
      file: `${WEB_APP}/src/features/shop/components/promotion-code-field.tsx`,
      components: ["badge", "button", "dialog", "field", "input"],
      glue: [],
    },
  },
  {
    slug: "calendar-view",
    title: "Calendar view",
    blocks: ["calendar"],
    kind: "screen",
    description:
      "A month and week calendar of events with a dialog to add one.",
    web: {
      file: `${WEB_APP}/src/features/calendar/components/calendar-view.tsx`,
      components: ["badge", "button", "card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "booking-page",
    title: "Booking page",
    blocks: ["bookings"],
    kind: "screen",
    description:
      "A public page that shows open slots and books one without overlaps.",
    web: {
      file: `${WEB_APP}/src/features/bookings/components/booking-page.tsx`,
      components: ["button", "card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "availability-editor",
    title: "Availability editor",
    blocks: ["bookings"],
    kind: "component",
    description:
      "Weekly working hours and date overrides that set which slots can be booked.",
    web: {
      file: `${WEB_APP}/src/features/bookings/components/availability-editor.tsx`,
      components: ["badge", "card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "reminders-list",
    title: "Reminders list",
    blocks: ["reminders"],
    kind: "component",
    description:
      "The next events with the caller's reminders on each, to add a reminder at an offset before an event or remove one.",
    web: {
      file: `${WEB_APP}/src/features/calendar/components/reminders-list.tsx`,
      components: ["card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "drive-explorer",
    title: "Drive explorer",
    blocks: ["drive"],
    kind: "screen",
    description:
      "Folders and files with upload, rename, move and a breadcrumb trail, each file with its labels and the approval of its current version.",
    web: {
      file: `${WEB_APP}/src/features/drive/components/drive-explorer.tsx`,
      components: [
        "alert",
        "badge",
        "breadcrumb",
        "button",
        "card",
        "empty",
        "skeleton",
        "table",
      ],
      glue: [],
    },
  },
  {
    slug: "version-history",
    title: "Version history",
    blocks: ["versions"],
    kind: "component",
    description:
      "The saved versions of a record with a diff and a button to restore one.",
    web: {
      file: `${WEB_APP}/src/features/customers/components/version-history.tsx`,
      components: [
        "alert",
        "alert-dialog",
        "badge",
        "button",
        "card",
        "dialog",
        "empty",
        "skeleton",
      ],
      glue: [],
    },
  },
  {
    slug: "trash-bin",
    title: "Trash bin",
    blocks: ["trash"],
    kind: "screen",
    description:
      "Deleted records with buttons to restore them or delete them for good.",
    web: {
      file: `${WEB_APP}/src/features/trash/components/trash-bin.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "empty",
        "skeleton",
        "table",
      ],
      glue: [],
    },
  },
  {
    slug: "form-builder",
    title: "Form builder",
    blocks: ["forms"],
    kind: "screen",
    description:
      "An editor for form fields and a preview, with the responses in a table.",
    web: {
      file: `${WEB_APP}/src/features/forms/components/form-builder.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "empty",
        "skeleton",
        "table",
      ],
      glue: [],
    },
  },
  {
    slug: "post-board",
    title: "Post board",
    blocks: ["posts"],
    kind: "screen",
    description:
      "A feedback board's posts ranked by votes, with an upvote toggle, the roadmap status, moderation state and a New post dialog.",
    web: {
      file: `${WEB_APP}/src/features/community/components/post-board.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "dialog",
        "empty",
        "field",
        "input",
        "skeleton",
        "textarea",
      ],
      glue: [],
    },
  },
  {
    slug: "course-outline",
    title: "Course outline",
    blocks: ["courses"],
    kind: "component",
    description:
      "A course's modules and lessons in rank order, with the caller's progress, certificate and an Enroll button.",
    web: {
      file: `${WEB_APP}/src/features/courses/components/course-outline.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "empty",
        "progress",
        "skeleton",
      ],
      glue: [],
    },
  },
  {
    slug: "lesson-player",
    title: "Lesson player",
    blocks: ["courses"],
    kind: "screen",
    description:
      "One lesson's content with a Mark as done button, or its quiz, which the database grades on submit.",
    web: {
      file: `${WEB_APP}/src/features/courses/components/lesson-player.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "checkbox",
        "field",
        "input",
        "select",
        "skeleton",
        "textarea",
      ],
      glue: [],
    },
  },
  {
    slug: "csv-import-wizard",
    title: "CSV import wizard",
    blocks: ["imports"],
    kind: "screen",
    description:
      "A stepper that uploads a CSV, maps its columns, validates the rows and imports them.",
    web: {
      file: `${WEB_APP}/src/features/imports/components/csv-import-wizard.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "empty",
        "field",
        "select",
        "@reui/stepper",
        "table",
      ],
      glue: [],
    },
  },
  {
    slug: "templates-gallery",
    title: "Templates gallery",
    blocks: ["templates"],
    kind: "screen",
    description:
      "Templates in a grid with a preview and a button to create a record from one.",
    web: {
      file: `${WEB_APP}/src/features/templates/components/templates-gallery.tsx`,
      components: ["alert", "badge", "button", "card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "document-editor",
    title: "Document editor",
    blocks: ["documents"],
    kind: "screen",
    description:
      "A rich text editor for a document with autosave, collaborators and a suggestion mode that editors accept or reject.",
    web: {
      file: `${WEB_APP}/src/features/documents/components/document-editor.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "empty",
        "field",
        "input",
        "skeleton",
        "tabs",
        "textarea",
      ],
      glue: [],
    },
  },
];
