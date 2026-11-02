import type { CatalogBlock, CatalogPreset } from "@/lib/blocks";
import type { Snippet } from "@/lib/snippets";

import { blocks, catalogPresets } from "@/lib/blocks";

/** The presets the home page switcher offers, in order. */
export const SWITCHER_PRESETS = [
  "crm",
  "helpdesk",
  "erp",
  "projects",
  "commerce",
  "saas",
] as const;

/** The preset every other preset builds on; its blocks count as foundation. */
const FOUNDATION_PRESET = "saas";

export function getPreset(name: string): CatalogPreset | undefined {
  return catalogPresets.find((preset) => preset.name === name);
}

const foundation = new Set(getPreset(FOUNDATION_PRESET)?.blocks);

export interface PresetBlocks {
  /** The blocks the preset adds to the shared foundation, in catalog order. */
  readonly domain: readonly CatalogBlock[];
  /**
   * How many foundation blocks (organizations, memberships and so on) it
   * installs.
   */
  readonly foundationCount: number;
  readonly total: number;
}

export function presetBlocks(preset: CatalogPreset): PresetBlocks {
  const byName = new Map(blocks.map((block) => [block.name, block]));

  const found = preset.blocks.flatMap((name) => {
    const block = byName.get(name);

    return block === undefined ? [] : [block];
  });

  return {
    domain: found.filter((block) => !foundation.has(block.name)),
    foundationCount: found.filter((block) => foundation.has(block.name)).length,
    total: found.length,
  };
}

/** The config and commands that start an app from a preset. */
export function presetSnippet(preset: CatalogPreset) {
  return {
    filename: "better-supabase.config.ts",
    language: "ts",
    code: `import { defineConfig } from "better-supabase/config";

// ${preset.title}: installs ${String(preset.blocks.length)} blocks.
export default defineConfig({
  preset: "${preset.name}",
});

// pnpm better-supabase init --preset ${preset.name}
// pnpm better-supabase gen`,
  } satisfies Snippet;
}

/** The presets grouped by their group heading, in display order. */
export function presetGroups(): readonly {
  readonly title: string;
  readonly presets: readonly CatalogPreset[];
}[] {
  const groups = new Map<string, CatalogPreset[]>();

  for (const preset of catalogPresets) {
    groups.set(preset.groupTitle, [
      ...(groups.get(preset.groupTitle) ?? []),
      preset,
    ]);
  }

  return [...groups].map(([title, presets]) => ({ title, presets }));
}
