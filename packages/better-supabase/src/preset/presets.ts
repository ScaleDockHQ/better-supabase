import type { Preset, PresetConventions } from "./fields.ts";

import { PRESET_BLOCKS } from "./blocks.ts";
import { encodePreset } from "./code.ts";
import { DEFAULT_CONVENTIONS } from "./fields.ts";

/** Where a named preset sits in the `/create` and `init` pickers. */
export type PresetGroup =
  | "starters"
  | "products"
  | "ai"
  | "platforms"
  | "everything";

/** The preset groups in display order, with their headings. */
export const PRESET_GROUPS: Readonly<Record<PresetGroup, string>> = {
  starters: "Starters",
  products: "Products",
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
  | "chat"
  | "commerce"
  | "marketplace"
  | "scheduling"
  | "people"
  | "drive"
  | "docs"
  | "invoicing"
  | "forms"
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
      "SaaS plus parties, pipelines and engagements, with tags, comments, an activity feed, custom fields, saved views and search.",
    group: "products",
    blocks: [
      ...SAAS,
      "parties",
      "pipelines",
      "engagements",
      "tags",
      "comments",
      "activity",
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
      "activity",
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
      "SaaS plus a shared inbox, work items with SLAs, comments, an activity feed, attachments, tags, saved views, a knowledge base and search.",
    group: "products",
    blocks: [
      ...SAAS,
      "inbox",
      "work-items",
      "sla",
      "comments",
      "activity",
      "attachments",
      "tags",
      "saved-views",
      "knowledge",
      "search",
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
      "activity",
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
  "chat",
  "commerce",
  "marketplace",
  "scheduling",
  "people",
  "drive",
  "docs",
  "invoicing",
  "forms",
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
