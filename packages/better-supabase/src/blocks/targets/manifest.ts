import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { targetsSqlOptions } from "./options.ts";
import { createTargets } from "./targets.ts";

/** The `targets` block's manifest (ADR 0029). */
export const targetsBlock: BlockOf<"targets", typeof createTargets> =
  defineBlock({
    name: "targets",
    sql: ["targets"],
    options: { targets: targetsSqlOptions },
    create: createTargets,
    category: "crm",
    recipes: ["targets-progress"],
  });
