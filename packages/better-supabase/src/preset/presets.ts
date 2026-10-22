import type { Preset, PresetConventions } from "./fields.ts";

import { PRESET_BLOCKS } from "./blocks.ts";
import { encodePreset } from "./code.ts";
import { DEFAULT_CONVENTIONS } from "./fields.ts";

/** Where a named preset sits in the `/create` and `init` pickers. */
export type PresetGroup =
  | "starters"
  | "products"
  | "verticals"
  | "ai"
  | "platforms"
  | "everything";

/** The preset groups in display order, with their headings. */
export const PRESET_GROUPS: Readonly<Record<PresetGroup, string>> = {
  starters: "Starters",
  products: "Products",
  verticals: "Verticals",
  ai: "AI",
  platforms: "Platforms",
  everything: "Everything",
};

/** A named starting point: a block selection with the default conventions. */
export interface NamedPreset {
  readonly name: string;
  readonly title: string;
  readonly description: string;
  readonly group: PresetGroup;
  /** The blocks it selects; `resolvePreset` adds what they require. */
  readonly blocks: readonly string[];
  /** The conventions it sets over the defaults, such as a user scope. */
  readonly conventions?: Partial<PresetConventions>;
}

const SAAS: readonly string[] = [
  "organizations",
  "invitations",
  "teams",
  "profiles",
  "billing",
  "entitlements",
  "notifications",
  "audit",
  "api-keys",
  "settings",
  "onboarding",
  "outbox",
];

/** A named preset's name. */
export type PresetName =
  | "minimal"
  | "saas"
  | "consumer"
  | "crm"
  | "projects"
  | "helpdesk"
  | "commerce"
  | "marketplace"
  | "scheduling"
  | "people"
  | "drive"
  | "docs"
  | "invoicing"
  | "forms"
  | "property"
  | "field-service"
  | "clinic"
  | "lms"
  | "events"
  | "legal"
  | "spend"
  | "contracts"
  | "customer-success"
  | "logistics"
  | "pos"
  | "fitness"
  | "nonprofit"
  | "itsm"
  | "compliance"
  | "construction"
  | "claims"
  | "ai"
  | "ai-chat"
  | "ai-agents"
  | "developer-api"
  | "automation"
  | "enterprise"
  | "admin"
  | "everything";

/** The named presets, for `defineConfig({ preset })` and `/create`. */
export const PRESETS: Readonly<Record<PresetName, NamedPreset>> = {
  minimal: {
    name: "minimal",
    title: "Minimal",
    description: "User profiles, for an app without tenants yet.",
    group: "starters",
    blocks: ["profiles"],
  },
  saas: {
    name: "saas",
    title: "SaaS",
    description:
      "Organizations with invitations and teams, billing and entitlements, notifications, the audit log, API keys, settings and onboarding.",
    group: "starters",
    blocks: SAAS,
  },
  consumer: {
    name: "consumer",
    title: "Consumer app",
    description:
      "Data owned by each user, with profiles, linked identities, MFA, sessions, notifications and push.",
    group: "starters",
    blocks: [
      "profiles",
      "identities",
      "mfa",
      "sessions",
      "notifications",
      "push",
    ],
    conventions: { scope: "user" },
  },
  crm: {
    name: "crm",
    title: "CRM",
    description:
      "SaaS plus parties, pipelines and engagements, with tags, comments, custom fields, saved views and search.",
    group: "products",
    blocks: [
      ...SAAS,
      "parties",
      "pipelines",
      "engagements",
      "tags",
      "comments",
      "custom-fields",
      "saved-views",
      "search",
    ],
  },
  projects: {
    name: "projects",
    title: "Projects",
    description:
      "SaaS plus tags, comments, attachments, a state machine, ranked ordering, reminders and time tracking.",
    group: "products",
    blocks: [
      ...SAAS,
      "tags",
      "comments",
      "attachments",
      "state-machine",
      "rank",
      "reminders",
      "time-tracking",
    ],
  },
  helpdesk: {
    name: "helpdesk",
    title: "Help desk",
    description:
      "SaaS plus a shared inbox, work items with SLAs, comments, attachments, tags, saved views, a knowledge base and search.",
    group: "products",
    blocks: [
      ...SAAS,
      "inbox",
      "work-items",
      "sla",
      "comments",
      "attachments",
      "tags",
      "saved-views",
      "knowledge",
      "search",
    ],
  },
  commerce: {
    name: "commerce",
    title: "Commerce",
    description:
      "SaaS plus a product catalog, inventory, orders and promotions.",
    group: "products",
    blocks: [...SAAS, "catalog", "inventory", "orders", "promotions"],
  },
  marketplace: {
    name: "marketplace",
    title: "Marketplace",
    description:
      "SaaS plus parties, a product catalog, orders, invoices, reactions and share links.",
    group: "products",
    blocks: [
      ...SAAS,
      "parties",
      "catalog",
      "orders",
      "invoices",
      "reactions",
      "share-links",
    ],
  },
  scheduling: {
    name: "scheduling",
    title: "Scheduling",
    description:
      "SaaS plus calendars, bookings and reminders, for a clinic, a studio or a salon.",
    group: "products",
    blocks: [...SAAS, "calendar", "bookings", "reminders"],
  },
  people: {
    name: "people",
    title: "HR and people",
    description:
      "SaaS plus employees, hiring, time tracking, approvals, calendars and documents.",
    group: "products",
    blocks: [
      ...SAAS,
      "employees",
      "hiring",
      "time-tracking",
      "approvals",
      "calendar",
      "documents",
    ],
  },
  drive: {
    name: "drive",
    title: "Cloud drive",
    description:
      "SaaS plus a drive with attachments, share links, versions, trash and search.",
    group: "products",
    blocks: [
      ...SAAS,
      "drive",
      "attachments",
      "share-links",
      "versions",
      "trash",
      "search",
    ],
  },
  docs: {
    name: "docs",
    title: "Docs and wiki",
    description:
      "SaaS plus documents with versions, comments, reactions, templates, search and share links.",
    group: "products",
    blocks: [
      ...SAAS,
      "documents",
      "versions",
      "comments",
      "reactions",
      "templates",
      "search",
      "share-links",
    ],
  },
  invoicing: {
    name: "invoicing",
    title: "Invoicing",
    description:
      "SaaS plus parties, quotes, invoices and number sequences for their numbers.",
    group: "products",
    blocks: [...SAAS, "parties", "quotes", "invoices", "number-sequences"],
  },
  forms: {
    name: "forms",
    title: "Forms and surveys",
    description: "SaaS plus forms, templates and imports.",
    group: "products",
    blocks: [...SAAS, "forms", "templates", "imports"],
  },
  property: {
    name: "property",
    title: "Property management",
    description:
      "SaaS plus units in assets, leases with recurring charges on the ledger, tenants as parties with a guest portal, invoices and maintenance work items.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "assets",
      "leases",
      "ledger",
      "parties",
      "guests",
      "invoices",
      "work-items",
      "attachments",
      "reminders",
    ],
  },
  "field-service": {
    name: "field-service",
    title: "Field service",
    description:
      "SaaS plus a dispatch board for technicians, jobs as work items on assets, quotes to invoices, checklists as forms and a signature on completion.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "parties",
      "work-items",
      "dispatch",
      "assets",
      "quotes",
      "invoices",
      "forms",
      "signatures",
      "attachments",
    ],
  },
  clinic: {
    name: "clinic",
    title: "Clinic and therapy",
    description:
      "SaaS plus appointments, intake forms, note templates, consent signatures, encrypted custom fields, a read-access log and a client portal.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "calendar",
      "bookings",
      "forms",
      "templates",
      "signatures",
      "custom-fields",
      "guests",
      "reminders",
    ],
  },
  lms: {
    name: "lms",
    title: "Courses and learning",
    description:
      "SaaS plus courses with lessons and scored quizzes, enrollments with progress, comments and attachments.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "courses",
      "enrollments",
      "forms",
      "comments",
      "attachments",
    ],
  },
  events: {
    name: "events",
    title: "Events and ticketing",
    description:
      "SaaS plus tickets in a catalog, orders, bookings for capacity, QR passes with check-in, a waitlist and reminders.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "catalog",
      "orders",
      "bookings",
      "passes",
      "waitlist",
      "reminders",
    ],
  },
  legal: {
    name: "legal",
    title: "Legal practice",
    description:
      "SaaS plus clients as parties, time tracking billed from a rate card into invoices, a trust ledger, documents with versions and signatures.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "parties",
      "time-tracking",
      "billable-time",
      "invoices",
      "ledger",
      "documents",
      "versions",
      "signatures",
    ],
  },
  spend: {
    name: "spend",
    title: "Expenses and spend",
    description:
      "SaaS plus expenses with receipts and policies, approvals, reimbursements on the ledger and receipt files for AI extraction.",
    group: "verticals",
    blocks: [...SAAS, "expenses", "approvals", "attachments", "ai-files"],
  },
  contracts: {
    name: "contracts",
    title: "Contracts",
    description:
      "SaaS plus a contract lifecycle with renewals and obligations, counterparties, signatures, versions, approvals and reminders.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "contracts",
      "parties",
      "signatures",
      "versions",
      "approvals",
      "reminders",
    ],
  },
  "customer-success": {
    name: "customer-success",
    title: "Customer success",
    description:
      "SaaS plus accounts as parties, health scores, metrics, rules, NPS forms, playbooks as enrollments and engagements.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "parties",
      "engagements",
      "scores",
      "metrics",
      "rules",
      "forms",
      "enrollments",
      "reminders",
    ],
  },
  logistics: {
    name: "logistics",
    title: "Logistics and fleet",
    description:
      "SaaS plus orders, shipments with carrier tracking events, vehicles and depots in assets, and a dispatch board for routes.",
    group: "verticals",
    blocks: [...SAAS, "parties", "orders", "shipments", "assets", "dispatch"],
  },
  pos: {
    name: "pos",
    title: "Restaurants and POS",
    description:
      "SaaS plus a menu in the catalog, orders with a kitchen board, inventory, table bookings, promotions and loyalty points on the ledger.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "catalog",
      "orders",
      "inventory",
      "bookings",
      "promotions",
      "ledger",
    ],
  },
  fitness: {
    name: "fitness",
    title: "Fitness and memberships",
    description:
      "SaaS plus class schedules, recurring bookings with class credits on the ledger, and passes with check-in.",
    group: "verticals",
    blocks: [...SAAS, "calendar", "bookings", "passes", "ledger", "reminders"],
  },
  nonprofit: {
    name: "nonprofit",
    title: "Nonprofit fundraising",
    description:
      "SaaS plus donors as parties, donations and recurring gifts on the ledger, campaign targets and saved views for segments.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "parties",
      "donations",
      "ledger",
      "targets",
      "saved-views",
    ],
  },
  itsm: {
    name: "itsm",
    title: "IT service management",
    description:
      "SaaS plus tickets as work items with SLAs, approvals for changes, an asset registry, relations, incidents with a status page and a knowledge base.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "work-items",
      "sla",
      "approvals",
      "assets",
      "relations",
      "incidents",
      "knowledge",
    ],
  },
  compliance: {
    name: "compliance",
    title: "Compliance",
    description:
      "SaaS plus controls with recurring evidence, evidence files, policy documents with acknowledgements and reminders.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "controls",
      "attachments",
      "documents",
      "signatures",
      "reminders",
    ],
  },
  construction: {
    name: "construction",
    title: "Construction",
    description:
      "SaaS plus punch lists and RFIs as work items, sites in assets, daily logs as forms, drawings with versions and comments, and approvals for submittals.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "work-items",
      "assets",
      "forms",
      "attachments",
      "versions",
      "comments",
      "approvals",
    ],
  },
  claims: {
    name: "claims",
    title: "Insurance and claims",
    description:
      "SaaS plus claimants as parties, a claim state machine, approvals, attachments for evidence, SLAs and comments.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "parties",
      "state-machine",
      "approvals",
      "attachments",
      "sla",
      "comments",
    ],
  },
  ai: {
    name: "ai",
    title: "AI workspace",
    description:
      "SaaS plus AI chat, files, a knowledge base, memory, agents and background AI tasks.",
    group: "ai",
    blocks: [
      ...SAAS,
      "ai-chat",
      "ai-files",
      "knowledge",
      "memory",
      "agents",
      "ai-tasks",
    ],
  },
  "ai-chat": {
    name: "ai-chat",
    title: "AI chat",
    description:
      "SaaS plus AI chat with files, a knowledge base, memory, model providers and usage metering.",
    group: "ai",
    blocks: [
      ...SAAS,
      "ai-chat",
      "ai-files",
      "knowledge",
      "memory",
      "ai-providers",
      "usage",
    ],
  },
  "ai-agents": {
    name: "ai-agents",
    title: "AI agents",
    description:
      "SaaS plus agents with background tasks, approvals, connectors, credentials, workflows and metrics.",
    group: "ai",
    blocks: [
      ...SAAS,
      "agents",
      "ai-tasks",
      "approvals",
      "connectors",
      "credentials",
      "workflows",
      "metrics",
    ],
  },
  "developer-api": {
    name: "developer-api",
    title: "Developer API",
    description:
      "SaaS plus outgoing webhooks, usage metering, service principals and signing keys.",
    group: "platforms",
    blocks: [
      ...SAAS,
      "webhooks-out",
      "usage",
      "service-principals",
      "signing-keys",
    ],
  },
  automation: {
    name: "automation",
    title: "Workflow automation",
    description:
      "SaaS plus a workflow builder, workflows, jobs, outgoing webhooks, connectors and credentials.",
    group: "platforms",
    blocks: [
      ...SAAS,
      "workflow-builder",
      "workflows",
      "jobs",
      "webhooks-out",
      "connectors",
      "credentials",
    ],
  },
  enterprise: {
    name: "enterprise",
    title: "Enterprise-ready",
    description:
      "SaaS plus SSO, MFA, sessions, access requests, support sessions, data export and deletion, and grants.",
    group: "platforms",
    blocks: [
      ...SAAS,
      "sso",
      "mfa",
      "sessions",
      "access-requests",
      "support-sessions",
      "data-lifecycle",
      "grants",
    ],
  },
  admin: {
    name: "admin",
    title: "Internal admin",
    description:
      "SaaS plus feature flags, metrics, approvals, saved views and bulk actions.",
    group: "platforms",
    blocks: [...SAAS, "flags", "metrics", "approvals", "saved-views", "bulk"],
  },
  everything: {
    name: "everything",
    title: "Everything",
    description: "Every block, for demos and tests.",
    group: "everything",
    blocks: PRESET_BLOCKS.filter((name) => name !== null),
  },
};

/** The named presets in display order, grouped by `group`. */
export const PRESET_NAMES: readonly PresetName[] = [
  "minimal",
  "saas",
  "consumer",
  "crm",
  "projects",
  "helpdesk",
  "commerce",
  "marketplace",
  "scheduling",
  "people",
  "drive",
  "docs",
  "invoicing",
  "forms",
  "property",
  "field-service",
  "clinic",
  "lms",
  "events",
  "legal",
  "spend",
  "contracts",
  "customer-success",
  "logistics",
  "pos",
  "fitness",
  "nonprofit",
  "itsm",
  "compliance",
  "construction",
  "claims",
  "ai",
  "ai-chat",
  "ai-agents",
  "developer-api",
  "automation",
  "enterprise",
  "admin",
  "everything",
];

export function isPresetName(value: string): value is PresetName {
  return PRESET_NAMES.some((name) => name === value);
}

/** The named preset as a `Preset`: the default conventions, then its own. */
export function namedPreset(name: PresetName): Preset {
  const { blocks, conventions } = PRESETS[name];

  return { ...DEFAULT_CONVENTIONS, ...conventions, blocks };
}

/** The preset `/create` and `init` start from. */
export const DEFAULT_PRESET_NAME = "saas" as const;

/** The default preset as a `Preset`, so a new design can start from it. */
export function defaultPreset(): Preset {
  return namedPreset(DEFAULT_PRESET_NAME);
}

/** The default preset's code, for a `/create` URL or `init --preset`. */
export function defaultPresetCode(): string {
  return encodePreset(defaultPreset());
}
