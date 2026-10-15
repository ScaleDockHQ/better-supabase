import type { Block } from "../define-block.ts";

import { defineBlock, optionKeys } from "../define-block.ts";

/** The `reserved-slugs` block's manifest (ADR 0029). */
export const reservedSlugsBlock: Block<"reserved-slugs"> = defineBlock({
  name: "reserved-slugs",
  sql: ["reserved-slugs"],
  options: {
    "reserved-slugs": optionKeys(["maxLength", "minLength", "slugs"]),
  },
  category: "foundation",
});
