import type { Preset } from "./fields.ts";

import { PRESET_BLOCKS } from "./blocks.ts";
import { DEFAULT_CONVENTIONS } from "./fields.ts";

/** A named starting point: a block selection with the default conventions. */
export interface NamedPreset {
  readonly name: string;
  readonly title: string;
  readonly description: string;
  /** The blocks it selects; `resolvePreset` adds what they require. */
  readonly blocks: readonly string[];
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
  | "crm"
  | "projects"
  | "commerce"
  | "scheduling"
  | "ai"
  | "everything";

/** The named presets, for `defineConfig({ preset })` and `/create`. */
export const PRESETS: Readonly<Record<PresetName, NamedPreset>> = {
  minimal: {
    name: "minimal",
    title: "Minimal",
    description: "User profiles, for an app without tenants yet.",
    blocks: ["profiles"],
  },
  saas: {
    name: "saas",
    title: "SaaS",
    description:
      "Organizations with invitations and teams, billing and entitlements, notifications, the audit log, API keys, settings and onboarding.",
    blocks: SAAS,
  },
  crm: {
    name: "crm",
    title: "CRM",
    description:
      "SaaS plus parties, pipelines and engagements, with tags, comments, custom fields, saved views and search.",
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
  commerce: {
    name: "commerce",
    title: "Commerce",
    description:
      "SaaS plus a product catalog, inventory, orders and promotions.",
    blocks: [...SAAS, "catalog", "inventory", "orders", "promotions"],
  },
  scheduling: {
    name: "scheduling",
    title: "Scheduling",
    description: "SaaS plus calendars, bookings and reminders.",
    blocks: [...SAAS, "calendar", "bookings", "reminders"],
  },
  ai: {
    name: "ai",
    title: "AI",
    description:
      "SaaS plus AI chat, files, a knowledge base, memory, agents and background AI tasks.",
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
  everything: {
    name: "everything",
    title: "Everything",
    description: "Every block, for demos and tests.",
    blocks: PRESET_BLOCKS.filter((name) => name !== null),
  },
};

/** The named presets in display order. */
export const PRESET_NAMES: readonly PresetName[] = [
  "minimal",
  "saas",
  "crm",
  "projects",
  "commerce",
  "scheduling",
  "ai",
  "everything",
];

export function isPresetName(value: string): value is PresetName {
  return PRESET_NAMES.some((name) => name === value);
}

/** The named preset as a `Preset`, with the default conventions. */
export function namedPreset(name: PresetName): Preset {
  return { ...DEFAULT_CONVENTIONS, blocks: PRESETS[name].blocks };
}
