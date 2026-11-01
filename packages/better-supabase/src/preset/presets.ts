import type { Preset, PresetConventions } from "./fields.ts";

import { PRESET_CATALOG } from "./catalog.generated.ts";
import { DEFAULT_CONVENTIONS } from "./fields.ts";
import {
  CONTROLLED_DOCUMENTS,
  ERP,
  PUBLIC_MEDIA,
  QUALITY,
  QUOTE_TO_ORDER,
  SAAS,
  SAAS_LINKED,
  TICKETS,
} from "./preset-blocks.ts";

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
  /** The `blocks` entries it writes: its nouns and extra instances. */
  readonly instances?: Preset["instances"];
}

/** A named preset's name. */
export type PresetName =
  | "minimal"
  | "saas"
  | "consumer"
  | "crm"
  | "projects"
  | "helpdesk"
  | "chat"
  | "commerce"
  | "cms"
  | "erp"
  | "manufacturing"
  | "pim"
  | "marketplace"
  | "scheduling"
  | "people"
  | "psa"
  | "ats"
  | "intranet"
  | "drive"
  | "docs"
  | "invoicing"
  | "forms"
  | "property"
  | "field-service"
  | "clinic"
  | "care"
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
  | "qms"
  | "ehs"
  | "isms"
  | "construction"
  | "claims"
  | "community"
  | "feedback"
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
      "SaaS plus parties, pipelines, deals, quotes, sales targets and engagements, with synced mailboxes, email sequences, segments, assignment queues, enrichment, forecasts and lead scoring, a job queue for the sequence timers, tags, comments, an activity feed, custom fields, saved views and search.",
    group: "products",
    blocks: [
      ...SAAS_LINKED,
      "crm",
      "tags",
      "comments",
      "timeline",
      "custom-fields",
      "saved-views",
      "search",
    ],
  },
  projects: {
    name: "projects",
    title: "Projects",
    description:
      "SaaS plus tags, comments, an activity feed, attachments, a state machine, ranked ordering, reminders and time tracking.",
    group: "products",
    blocks: [
      ...SAAS,
      "tags",
      "comments",
      "timeline",
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
      "SaaS plus a shared inbox whose new conversations open work items with SLAs, default automations, a job queue, comments, an activity feed, attachments, tags, saved views, a knowledge base and search.",
    group: "products",
    blocks: [
      ...SAAS_LINKED,
      "support",
      "comments",
      "timeline",
      "attachments",
      "tags",
      "saved-views",
      "search",
      "automations",
      "queue",
    ],
  },
  chat: {
    name: "chat",
    title: "Team chat",
    description:
      "SaaS plus channels, direct messages, threads, mentions, reactions and files, kept live over Realtime.",
    group: "products",
    blocks: [...SAAS, "messaging", "channels", "reactions", "attachments"],
  },
  commerce: {
    name: "commerce",
    title: "Commerce",
    description:
      "SaaS plus a product catalog, inventory, orders and promotions.",
    group: "products",
    blocks: [...SAAS, "commerce"],
  },
  cms: {
    name: "cms",
    title: "CMS",
    description:
      "SaaS plus pages and posts with locales and scheduled publishing, versions, publish approvals, public media, tags, comments, search and a job queue for the publish timer.",
    group: "products",
    blocks: [...SAAS, "cms", "tags", "comments", "search", "queue"],
    instances: { content: { options: { requireApproval: true } } },
  },
  erp: {
    name: "erp",
    title: "ERP",
    description:
      "SaaS plus parties, a product catalog, stock by location, quotes priced from the catalog that become orders when accepted, orders that invoice when paid, purchase bills matched to purchase orders and receipts, the books every document posts to, bank statements reconciled against them, approvals for purchase requisitions, employees with time and leave, expenses and saved views.",
    group: "products",
    blocks: [...SAAS_LINKED, ...ERP],
    instances: QUOTE_TO_ORDER,
  },
  manufacturing: {
    name: "manufacturing",
    title: "Manufacturing",
    description:
      "ERP plus bills of materials and production orders, material requirements that raise purchase requisitions, incoming and in-process inspections, cases for nonconformities and qualifications for the people and equipment on the floor.",
    group: "products",
    blocks: [
      ...SAAS_LINKED,
      ...ERP,
      "manufacturing",
      "inspections",
      "cases",
      "qualifications",
    ],
    instances: {
      ...QUOTE_TO_ORDER,
      manufacturing: { options: { purchaseSuggestions: "requisition" } },
      inventory: { options: { receiptInspection: "inspection" } },
    },
  },
  pim: {
    name: "pim",
    title: "Product information",
    description:
      "SaaS plus a product catalog with sales channels, translations and public product media, custom fields, imports, bulk edits, tags, saved views and search.",
    group: "products",
    blocks: [
      ...SAAS,
      "catalog",
      "attachments",
      "custom-fields",
      "imports",
      "bulk",
      "tags",
      "saved-views",
      "search",
    ],
    instances: PUBLIC_MEDIA,
  },
  marketplace: {
    name: "marketplace",
    title: "Marketplace",
    description:
      "SaaS plus parties, a product catalog, orders, invoices, reactions and share links.",
    group: "products",
    blocks: [
      ...SAAS_LINKED,
      "contacts",
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
    blocks: [...SAAS, "scheduling"],
  },
  people: {
    name: "people",
    title: "HR and people",
    description:
      "SaaS plus employees, hiring that preboards each hired candidate, time tracking, approvals, calendars and documents.",
    group: "products",
    blocks: [
      ...SAAS_LINKED,
      "employees",
      "hiring",
      "time-tracking",
      "approvals",
      "calendar",
      "documents",
      "automations",
    ],
  },
  psa: {
    name: "psa",
    title: "Professional services",
    description:
      "SaaS plus clients, tasks, time tracking priced from rate cards, a staffing roster, expenses, approvals, quotes, contracts and invoices that bill the approved time, with numbering, comments, an activity feed, attachments, tags, saved views, search and automations.",
    group: "products",
    blocks: [
      ...SAAS_LINKED,
      "contacts",
      "tasks",
      "time-tracking",
      "billable-time",
      "shifts",
      "expenses",
      "approvals",
      "quotes",
      "contracts",
      "invoices",
      "numbering",
      "comments",
      "timeline",
      "attachments",
      "tags",
      "saved-views",
      "search",
      "automations",
    ],
  },
  ats: {
    name: "ats",
    title: "Applicant tracking",
    description:
      "SaaS plus hiring (candidates, stages and offers), application forms, interview scheduling on calendars and bookings, offer templates and signatures, approvals, reminders, comments, an activity feed, attachments, tags, saved views and search.",
    group: "products",
    blocks: [
      ...SAAS_LINKED,
      "recruiting",
      "forms",
      "bookings",
      "templates",
      "signatures",
      "approvals",
      "reminders",
      "comments",
      "timeline",
      "attachments",
      "tags",
      "saved-views",
      "search",
      "automations",
    ],
  },
  intranet: {
    name: "intranet",
    title: "Intranet",
    description:
      "SaaS plus company announcements, a knowledge base, a shared drive, channels, reactions and comments, a staff directory, a company calendar, policies that people acknowledge, tags, saved views and search.",
    group: "products",
    blocks: [
      ...SAAS,
      "announcements",
      "knowledge",
      "drive",
      "channels",
      "reactions",
      "comments",
      "employees",
      "calendar",
      "acknowledgements",
      "attachments",
      "tags",
      "saved-views",
      "search",
    ],
  },
  drive: {
    name: "drive",
    title: "Cloud drive",
    description:
      "SaaS plus a drive with attachments, share links, versions, trash and search.",
    group: "products",
    blocks: [...SAAS, "filespace"],
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
      "timeline",
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
    blocks: [...SAAS_LINKED, "contacts", "quotes", "invoices", "numbering"],
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
      "SaaS plus units in assets, leases with rent and deposits on the ledger and maintenance requests, tenants as parties with a guest portal, comments and attachments.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "assets",
      "leases",
      "ledger",
      "contacts",
      "guests",
      "comments",
      "attachments",
      "reminders",
    ],
    instances: {
      maintenance: {
        block: "tasks",
        names: { task: "maintenance_request" },
        tables: { projects: null, iterations: null },
        options: { prefix: "MR-" },
      },
    },
  },
  "field-service": {
    name: "field-service",
    title: "Field service",
    description:
      "SaaS plus a dispatch board of work orders at customer assets, parts from inventory, quotes to invoices, checklists as forms and a signature on completion.",
    group: "verticals",
    blocks: [
      ...SAAS_LINKED,
      "contacts",
      "dispatch",
      "assets",
      "inventory",
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
      "SaaS plus appointments, intake forms, note templates, consent signatures, field encryption for sensitive values, a client portal and reminders.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "calendar",
      "bookings",
      "forms",
      "templates",
      "signatures",
      "custom-fields",
      "field-encryption",
      "guests",
      "reminders",
    ],
  },
  care: {
    name: "care",
    title: "Care",
    description:
      "SaaS plus clients and their representatives as contacts with record teams and a read log, consents, progress notes, care plans, vital signs, medication rounds with double checks, funding awards and claims, shifts, qualifications and training, incidents and complaints as cases, and controlled protocols in the drive.",
    group: "verticals",
    blocks: [...SAAS, "care"],
  },
  lms: {
    name: "lms",
    title: "Courses and learning",
    description:
      "SaaS plus courses with lessons, quizzes graded by forms and certificates, enrollments with progress, comments and attachments.",
    group: "verticals",
    blocks: [...SAAS, "learning", "forms", "comments", "attachments"],
  },
  events: {
    name: "events",
    title: "Events and ticketing",
    description:
      "SaaS plus tickets in a catalog, orders, bookings for capacity, QR passes signed with signing keys and checked in, a waitlist and reminders.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "catalog",
      "orders",
      "events",
      "signing-keys",
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
      "contacts",
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
      "SaaS plus a contract lifecycle with renewals and obligations, counterparties as parties, signatures on a frozen version and reminders.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "contracts",
      "contacts",
      "signatures",
      "versions",
      "reminders",
    ],
  },
  "customer-success": {
    name: "customer-success",
    title: "Customer success",
    description:
      "SaaS plus accounts as parties, health scores from rules and metrics, NPS forms, playbooks as enrollments and engagements.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "contacts",
      "activities",
      "scores",
      "metrics",
      "automations",
      "forms",
      "enrollments",
      "reminders",
    ],
  },
  logistics: {
    name: "logistics",
    title: "Logistics and fleet",
    description:
      "SaaS plus shippers as parties, orders, shipments with carrier labels and tracking, and depots and vehicles in assets.",
    group: "verticals",
    blocks: [...SAAS, "contacts", "orders", "shipments", "assets"],
  },
  pos: {
    name: "pos",
    title: "Restaurants and POS",
    description:
      "SaaS plus a menu in the catalog, orders with a kitchen board, inventory, table bookings, promotions, loyalty points on the ledger, and till sessions with cash counts.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "catalog",
      "orders",
      "inventory",
      "bookings",
      "promotions",
      "ledger",
      "tills",
    ],
  },
  fitness: {
    name: "fitness",
    title: "Fitness and memberships",
    description:
      "SaaS plus class schedules, bookings, and passes with check-in and class credits, signed with signing keys, plus reminders.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "calendar",
      "bookings",
      "passes",
      "signing-keys",
      "reminders",
    ],
  },
  nonprofit: {
    name: "nonprofit",
    title: "Nonprofit fundraising",
    description:
      "SaaS plus donors as parties, gifts and pledges on the ledger, numbered tax receipts, campaign targets and saved views for segments.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "contacts",
      "donations",
      "ledger",
      "numbering",
      "goals",
      "saved-views",
    ],
  },
  itsm: {
    name: "itsm",
    title: "IT service management",
    description:
      "SaaS plus tickets as work items with SLAs, approvals for changes, an asset registry, relations, incidents with a status page, a knowledge base and a job queue for the SLA timers.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "tasks",
      "sla",
      "approvals",
      "assets",
      "relations",
      "incidents",
      "knowledge",
      "queue",
    ],
    instances: TICKETS,
  },
  compliance: {
    name: "compliance",
    title: "Compliance",
    description:
      "SaaS plus frameworks and controls with evidence, recurring evidence tasks and versioned policies that members acknowledge, with evidence files.",
    group: "verticals",
    blocks: [...SAAS, "compliance", "attachments"],
  },
  qms: {
    name: "qms",
    title: "Quality management",
    description:
      "SaaS plus controlled documents, cases for nonconformities, complaints and changes, audits and inspections, a risk register, qualifications and acknowledgements.",
    group: "verticals",
    blocks: [...SAAS, ...QUALITY, "posts"],
    instances: CONTROLLED_DOCUMENTS,
  },
  ehs: {
    name: "ehs",
    title: "Environment, health and safety",
    description:
      "SaaS plus incidents and near misses as cases, safety inspections, a risk register, training and licences as qualifications, equipment in assets and acknowledged procedures.",
    group: "verticals",
    blocks: [...SAAS, ...QUALITY],
  },
  isms: {
    name: "isms",
    title: "Information security",
    description:
      "SaaS plus security controls and policies, a risk register, internal audits, security incidents as cases, acknowledgements and a drive for documented information.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "compliance",
      "risks",
      "inspections",
      "cases",
      "acknowledgements",
      "drive",
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
      "tasks",
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
      "SaaS plus claimants as parties, a claim state machine, approvals, attachments for evidence, SLAs on a job queue and comments.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "contacts",
      "state-machine",
      "approvals",
      "attachments",
      "sla",
      "comments",
      "queue",
    ],
  },
  community: {
    name: "community",
    title: "Community",
    description:
      "SaaS plus forum boards of posts with votes and replies, chat channels, reactions, moderation with reports and bans, post scores from votes, tags and search.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "posts",
      "messaging",
      "channels",
      "comments",
      "reactions",
      "moderation",
      "scores",
      "tags",
      "search",
    ],
  },
  feedback: {
    name: "feedback",
    title: "Product feedback",
    description:
      "SaaS plus feedback boards of voted ideas with roadmap statuses, replies, moderation, ideas linked to the work items that ship them, tags and search.",
    group: "verticals",
    blocks: [
      ...SAAS,
      "posts",
      "comments",
      "reactions",
      "moderation",
      "tasks",
      "relations",
      "tags",
      "search",
    ],
  },
  ai: {
    name: "ai",
    title: "AI workspace",
    description:
      "SaaS plus AI chat, files, a knowledge base, memory, agents, and background AI tasks and file ingestion on a job queue.",
    group: "ai",
    blocks: [
      ...SAAS,
      "ai-chat",
      "ai-files",
      "knowledge",
      "memory",
      "agents",
      "ai-schedules",
      "queue",
    ],
  },
  "ai-chat": {
    name: "ai-chat",
    title: "AI chat",
    description:
      "SaaS plus AI chat with files, a knowledge base, memory, model providers, usage metering and a job queue for file ingestion.",
    group: "ai",
    blocks: [
      ...SAAS,
      "ai-chat",
      "ai-files",
      "knowledge",
      "memory",
      "ai-keys",
      "usage",
      "queue",
    ],
  },
  "ai-agents": {
    name: "ai-agents",
    title: "AI agents",
    description:
      "SaaS plus agents with background tasks, approvals, connectors, credentials, workflows, metrics and a job queue for the timers.",
    group: "ai",
    blocks: [
      ...SAAS,
      "agents",
      "ai-schedules",
      "approvals",
      "connectors",
      "credentials",
      "workflows",
      "metrics",
      "queue",
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
      "service-accounts",
      "signing-keys",
    ],
  },
  automation: {
    name: "automation",
    title: "Workflow automation",
    description:
      "SaaS plus a workflow builder, workflows that automations start, jobs, outgoing webhooks, connectors and credentials.",
    group: "platforms",
    blocks: [
      ...SAAS,
      "workflow-editor",
      "workflows",
      "queue",
      "webhooks-out",
      "connectors",
      "credentials",
      "automations",
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
      "impersonation",
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
    blocks: PRESET_CATALOG.blocks.map((block) => block.name),
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
  "chat",
  "commerce",
  "cms",
  "erp",
  "manufacturing",
  "pim",
  "marketplace",
  "scheduling",
  "people",
  "psa",
  "ats",
  "intranet",
  "drive",
  "docs",
  "invoicing",
  "forms",
  "property",
  "field-service",
  "clinic",
  "care",
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
  "qms",
  "ehs",
  "isms",
  "construction",
  "claims",
  "community",
  "feedback",
  "ai",
  "ai-chat",
  "ai-agents",
  "developer-api",
  "automation",
  "enterprise",
  "admin",
  "everything",
];

export function isPresetName(value: unknown): value is PresetName {
  return PRESET_NAMES.some((name) => name === value);
}

/** The named preset as a `Preset`: the default conventions, then its own. */
export function namedPreset(name: PresetName): Preset {
  const { blocks, conventions, instances } = PRESETS[name];

  return {
    ...DEFAULT_CONVENTIONS,
    ...conventions,
    blocks,
    ...(instances === undefined ? {} : { instances }),
  };
}

/** The preset `/create` and `init` start from. */
export const DEFAULT_PRESET_NAME = "saas" as const;

/** The default preset as a `Preset`, so a new design can start from it. */
export function defaultPreset(): Preset {
  return namedPreset(DEFAULT_PRESET_NAME);
}
