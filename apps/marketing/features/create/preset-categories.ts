import type { PresetName } from "better-supabase/preset";

import type { CategoryName } from "@/features/blocks/categories";

/** The catalog category whose icon and hue stand for each preset. */
export const PRESET_CATEGORY = {
  minimal: "Foundation",
  saas: "Collaboration",
  crm: "CRM & sales",
  projects: "Work",
  commerce: "Billing & commerce",
  scheduling: "Scheduling",
  ai: "AI",
  everything: "Platform",
} as const satisfies Readonly<Record<PresetName, CategoryName>>;
