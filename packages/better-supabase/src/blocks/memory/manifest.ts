import type { BlockOf } from "../define-block.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createMemory } from "./memory.ts";

/** The `memory` block's manifest (ADR 0029). */
export const memoryBlock: BlockOf<"memory", typeof createMemory> = defineBlock({
  name: "memory",
  sql: ["memory"],
  options: {
    memory: optionKeys(["dimensions", "type", "textSearch", "maxContent"]),
  },
  create: createMemory,
  category: "ai",
});
