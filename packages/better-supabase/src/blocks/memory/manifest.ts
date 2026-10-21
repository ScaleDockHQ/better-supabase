import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createMemory } from "./memory.ts";
import { memorySqlOptions } from "./options.ts";

/** The `memory` block's manifest (ADR 0029). */
export const memoryBlock: BlockOf<"memory", typeof createMemory> = defineBlock({
  name: "memory",
  sql: ["memory"],
  options: { memory: memorySqlOptions },
  create: createMemory,
  category: "ai",
});
