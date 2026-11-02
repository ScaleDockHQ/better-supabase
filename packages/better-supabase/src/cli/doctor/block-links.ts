import type { DoctorContext, FindingInput } from "./rules.ts";

import { PRESET_CATALOG } from "../../preset/index.ts";

/**
 * Declared conversion and relation links between installed blocks while the
 * relations block is missing (BS353). The conversion still runs through the
 * source row's origin columns, but no lineage link is recorded.
 */
export function linksWithoutRelations(context: DoctorContext): FindingInput[] {
  const installed = new Set(
    Object.entries(context.config.blocks).map(([instance, entry]) =>
      typeof entry?.block === "string" ? entry.block : instance,
    ),
  );

  if (installed.has("relations")) {
    return [];
  }

  return PRESET_CATALOG.blocks
    .filter((block) => installed.has(block.name))
    .flatMap((block) =>
      (block.links ?? [])
        .filter(
          (link) =>
            (link.kind === "conversion" || link.kind === "relation") &&
            installed.has(link.target.block),
        )
        .map((link): FindingInput => ({
          message: `${block.name} declares the ${link.kind} link "${link.key}" to ${link.target.block}, and relations is not installed, so no lineage link is written. Run better-supabase add relations.`,
          target: `blocks.${block.name}`,
        })),
    );
}
