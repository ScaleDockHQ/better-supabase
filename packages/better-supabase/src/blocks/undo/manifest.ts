import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createUndo } from "./undo.ts";

/** The `undo` block's manifest (ADR 0029). */
export const undoBlock: BlockOf<"undo", typeof createUndo> = defineBlock({
  name: "undo",
  create: createUndo,
  client: "undo",
  category: "work",
});
