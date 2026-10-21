import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createKnowledge } from "./knowledge.ts";
import { knowledgeSqlOptions } from "./options.ts";

/** The `knowledge` block's manifest (ADR 0029). */
export const knowledgeBlock: BlockOf<
  "knowledge",
  typeof createKnowledge,
  Record<never, never>,
  { readonly files: "optional" }
> = defineBlock({
  name: "knowledge",
  sql: ["knowledge"],
  options: { knowledge: knowledgeSqlOptions },
  consumes: { files: "optional" },
  create: createKnowledge,
  category: "ai",
  recipes: ["knowledge-upload"],
});
