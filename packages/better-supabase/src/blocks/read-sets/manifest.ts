import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";

/** The `read-sets` block's manifest (ADR 0029). */
export const readSetsBlock: Block<"read-sets"> = defineBlock({
  name: "read-sets",
  sql: ["read-sets"],
  category: "database",
  entities: { read_set: { mutability: "read-only" } },
  description:
    "One `stable` function per `defineReadSet` in `readSets`, so `db.$many(readSet, params)` is a single GET.",
});
