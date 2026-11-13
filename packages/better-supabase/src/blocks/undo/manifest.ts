import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createUndo } from "./undo.ts";

/** The `undo` block's manifest (ADR 0029). */
export const undoBlock: BlockOf<"undo", typeof createUndo> = defineBlock({
  name: "undo",
  create: createUndo,
  client: "undo",
  category: "work",
  entities: { undo: { mutability: "append-only", emits: { create: false } } },
  description:
    "Applies the undo token a block method returns, running its inverse calls in order as the caller.",
});
