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
  entities: { memory: { mutability: "append-only", emits: { create: false } } },
  description:
    "Memory for AI assistants: core memory as files under /memories edited with view, create, str_replace, insert, delete and rename with version checks; archival facts with hybrid similarity search; message embeddings to recall earlier chats, skipped for temporary chats; and versioned documents under an opaque scope key for agent runtimes such as eve.",
});
