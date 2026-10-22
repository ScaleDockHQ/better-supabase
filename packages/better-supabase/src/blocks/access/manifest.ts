import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createAccess } from "./access.ts";
import { accessSqlOptions } from "./options.ts";

/** The `access` block's manifest (ADR 0029). */
export const accessBlock: BlockOf<"access", typeof createAccess> = defineBlock({
  name: "access",
  sql: ["access"],
  options: { access: accessSqlOptions },
  create: createAccess,
  category: "identity",
  recipes: ["can"],
});
