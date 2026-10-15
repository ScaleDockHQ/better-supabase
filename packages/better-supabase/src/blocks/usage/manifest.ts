import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { usageSqlOptions } from "./options.ts";
import { createUsage } from "./usage.ts";

/** The `usage` block's manifest (ADR 0029). */
export const usageBlock: BlockOf<"usage", typeof createUsage> = defineBlock({
  name: "usage",
  sql: ["usage"],
  options: {
    usage: usageSqlOptions,
  },
  create: createUsage,
  category: "commerce",
  recipes: ["usage-meter"],
});
