import type { PresetName } from "better-supabase/preset";

import type { CategoryName } from "@/features/blocks/categories";

/** The catalog category whose icon and hue stand for each preset. */
export const PRESET_CATEGORY = {
  minimal: "Tenancy & accounts",
  saas: "Tenancy & accounts",
  crm: "CRM & sales",
  projects: "Work management",
  commerce: "Billing & commerce",
  scheduling: "Scheduling",
  ai: "AI",
  everything: "Database primitives",
} as const satisfies Readonly<Record<PresetName, CategoryName>>;
