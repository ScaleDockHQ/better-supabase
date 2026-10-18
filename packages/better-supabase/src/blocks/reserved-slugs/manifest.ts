import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { reservedSlugsSqlOptions } from "./options.ts";

/** The `reserved-slugs` block's manifest (ADR 0029). */
export const reservedSlugsBlock: Block<"reserved-slugs"> = defineBlock({
  name: "reserved-slugs",
  sql: ["reserved-slugs"],
  options: {
    "reserved-slugs": reservedSlugsSqlOptions,
  },
  category: "tenancy",
});
