import type { ResolvedPreset } from "better-supabase/preset";

import {
  namedPreset,
  presetConfig,
  resolvePreset,
} from "better-supabase/preset";

/** The blocks a named preset installs, with what they require. */
export function presetBlocks(name: "psa" | "ats" | "intranet"): ResolvedPreset {
  return resolvePreset(namedPreset(name));
}

/** The `blocks` key of a `better-supabase.config.ts` for a preset. */
export function presetBlocksConfig(name: "psa" | "ats" | "intranet"): object {
  return presetConfig(presetBlocks(name)).blocks;
}
