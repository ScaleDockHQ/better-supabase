import type { CreateDesign } from "../preset/design.ts";
import type { Issue } from "./issue.ts";

import { PRESET_CATALOG } from "../preset/index.ts";

/**
 * The seed variants a design names that the catalog doesn't offer: a block that
 * doesn't exist, or a variant the block doesn't declare (ADR 0196).
 */
export function seedIssues(
  design: Pick<CreateDesign, "seeds">,
): readonly Issue[] {
  const issues: Issue[] = [];

  for (const [block, variant] of Object.entries(design.seeds?.variants ?? {})) {
    const path = `/seeds/variants/${block.replaceAll("~", "~0").replaceAll("/", "~1")}`;
    const entry = PRESET_CATALOG.blocks.find((item) => item.name === block);

    if (entry === undefined) {
      issues.push({
        code: "unknown_seed_block",
        severity: "error",
        source: "seeds",
        path,
        table: block,
        message: `seeds.variants names "${block}", which is not a block`,
      });
    } else if (!(entry.seeds?.variants ?? []).includes(variant)) {
      const offered = entry.seeds?.variants ?? [];

      issues.push({
        code: "unknown_seed_variant",
        severity: "error",
        source: "seeds",
        path,
        table: block,
        message:
          offered.length === 0
            ? `seeds.variants.${block} is "${variant}", but ${block} declares no variants`
            : `seeds.variants.${block} is "${variant}"; ${block} offers ${offered.join(", ")}`,
      });
    }
  }

  return issues;
}
