import type { RecipeSource } from "./types.ts";

import { WEB_APP } from "./types.ts";

/** Recipes for the developer, operations and compliance blocks. */
export const OPERATIONS_RECIPES: readonly RecipeSource[] = [
  {
    slug: "webhook-endpoints",
    title: "Webhook endpoints",
    blocks: ["webhooks-out"],
    kind: "screen",
    description:
      "The organization's webhook endpoints with their recent deliveries and a retry button.",
    web: {
      file: `${WEB_APP}/src/features/webhooks/components/webhook-endpoints.tsx`,
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
    slug: "service-accounts-table",
    title: "Service accounts table",
    blocks: ["service-accounts"],
    kind: "component",
    description:
      "Machine identities with their scopes, last use and a button to disable one.",
    web: {
      file: `${WEB_APP}/src/features/service-principals/components/service-principals-table.tsx`,
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
    slug: "signing-keys-rotation",
    title: "Signing keys rotation",
    blocks: ["signing-keys"],
    kind: "component",
    description:
      "The active and previous signing keys with a button to rotate them.",
    web: {
      file: `${WEB_APP}/src/features/signing-keys/components/signing-keys-rotation.tsx`,
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
    slug: "data-export-delete",
    title: "Data export and delete",
    blocks: ["data-lifecycle"],
    kind: "screen",
    description:
      "Buttons to export the caller's data and to request account deletion, with the request status.",
    web: {
      file: `${WEB_APP}/src/features/privacy/components/privacy-settings.tsx`,
      components: ["alert", "badge", "button", "card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "job-runs-table",
    title: "Job runs table",
    blocks: ["queue"],
    kind: "component",
    description:
      "The latest background job runs with their status, attempts and error, and a button to retry a failed run.",
    web: {
      file: `${WEB_APP}/src/features/jobs/components/job-runs-table.tsx`,
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
    slug: "team-picker",
    title: "Team picker",
    blocks: ["teams"],
    kind: "component",
    description:
      "A select of the caller's teams in the active organization, to scope a page or assign work.",
    web: {
      file: `${WEB_APP}/src/features/work/components/team-picker.tsx`,
      components: ["button", "empty", "field", "input", "select"],
      glue: [],
    },
  },
  {
    slug: "contract-renewals",
    title: "Contract renewals",
    blocks: ["contracts"],
    kind: "component",
    description:
      "Active contracts with their value, end date and notice deadline, the nearest deadline first, so a renewal is decided in time.",
    web: {
      file: `${WEB_APP}/src/features/compliance/components/contract-renewals.tsx`,
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
    slug: "control-posture",
    title: "Control posture",
    blocks: ["compliance"],
    kind: "component",
    description:
      "One card per compliance framework with its passing, failing and not started controls, then the overdue evidence tasks.",
    web: {
      file: `${WEB_APP}/src/features/compliance/components/control-posture.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "empty",
        "progress",
        "skeleton",
        "table",
      ],
      glue: [],
    },
  },
  {
    slug: "acknowledgement-inbox",
    title: "Acknowledgement inbox",
    blocks: ["acknowledgements"],
    kind: "component",
    description:
      "The records a member is asked to read, soonest due first, with the due date and a button that acknowledges the version they read.",
    web: {
      file: `${WEB_APP}/src/features/acknowledgements/components/acknowledgement-inbox.tsx`,
      components: ["alert", "badge", "button", "card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "consent-register",
    title: "Consent register",
    blocks: ["consents"],
    kind: "component",
    description:
      "The purposes an organization asks consent for, with their lawful basis, version, how long a grant lasts and whether it needs a signature.",
    web: {
      file: `${WEB_APP}/src/features/compliance/components/consent-register.tsx`,
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
    slug: "status-page",
    title: "Status page",
    blocks: ["incidents"],
    kind: "screen",
    description:
      "A public status page: the overall status, each public component with its daily uptime, and the public incident updates.",
    web: {
      file: `${WEB_APP}/src/features/status/components/status-page.tsx`,
      components: ["alert", "badge", "button", "card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "trial-balance",
    title: "Trial balance",
    blocks: ["accounting"],
    kind: "component",
    description:
      "Total assets, liabilities and equity and this year's net income, then each account's debit, credit and balance with the totals.",
    web: {
      file: `${WEB_APP}/src/features/accounting/components/trial-balance.tsx`,
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
    slug: "production-order-board",
    title: "Production order board",
    blocks: ["manufacturing"],
    kind: "component",
    description:
      "Production orders in status columns from draft to done; dragging a draft to Released releases it, and a running order to Done completes it.",
    web: {
      file: `${WEB_APP}/src/features/manufacturing/components/production-order-board.tsx`,
      components: ["badge", "card", "@reui/kanban"],
      glue: [],
    },
  },
  {
    slug: "bank-reconciliation",
    title: "Bank reconciliation",
    blocks: ["banking"],
    kind: "component",
    description:
      "Each bank account's statement balance and what is left to match, then its latest transactions; an unmatched one offers its best invoice to match or can be ignored.",
    web: {
      file: `${WEB_APP}/src/features/banking/components/bank-reconciliation.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "empty",
        "skeleton",
        "@reui/frame",
        "@reui/data-grid",
      ],
      glue: [],
    },
  },
  {
    slug: "payroll-runs",
    title: "Payroll runs",
    blocks: ["payroll-export"],
    kind: "screen",
    description:
      "The organization's payroll runs, newest period first, with their line count, export format and whether they are locked.",
    web: {
      file: `${WEB_APP}/src/features/payroll-export/components/payroll-runs.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "empty",
        "skeleton",
        "table",
        "@reui/frame",
      ],
      glue: [],
    },
  },
];
