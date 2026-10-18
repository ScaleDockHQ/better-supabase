import type { PresetName } from "better-supabase/preset";

import type { CategoryName } from "@/features/blocks/categories";

/** The catalog category whose icon and hue stand for each preset. */
export const PRESET_CATEGORY = {
  minimal: "Tenancy & accounts",
  saas: "Tenancy & accounts",
  consumer: "Identity & access",
  crm: "CRM & sales",
  projects: "Work management",
  helpdesk: "Notifications & messaging",
  commerce: "Billing & commerce",
  marketplace: "Billing & commerce",
  scheduling: "Scheduling",
  people: "People",
  drive: "Content & files",
  docs: "Content & files",
  invoicing: "Billing & commerce",
  forms: "Content & files",
  ai: "AI",
  "ai-chat": "AI",
  "ai-agents": "AI",
  "developer-api": "Developer platform",
  automation: "Automation",
  enterprise: "Identity & access",
  admin: "Admin & compliance",
  everything: "Database primitives",
} as const satisfies Readonly<Record<PresetName, CategoryName>>;
