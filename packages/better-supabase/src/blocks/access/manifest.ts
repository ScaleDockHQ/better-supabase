import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { accessSqlOptions } from "./options.ts";

/** The `access` block's manifest (ADR 0029). */
export const accessBlock: Block<"access"> = defineBlock({
  name: "access",
  sql: ["access"],
  options: {
    access: accessSqlOptions,
  },
  category: "foundation",
});
