import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { updatedAtSqlOptions } from "./options.ts";

/** The `updated-at` block's manifest (ADR 0029). */
export const updatedAtBlock: Block<"updated-at"> = defineBlock({
  name: "updated-at",
  sql: ["updated-at"],
  options: { "updated-at": updatedAtSqlOptions },
  category: "database",
  entities: { updated_at: { mutability: "read-only" } },
  description: "Keeps an updated_at column current on every update.",
  extension: "updatedAtExtension",
});
