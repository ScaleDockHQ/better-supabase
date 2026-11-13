import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createAiFiles } from "./ai-files.ts";
import { aiFilesSqlOptions } from "./options.ts";

/** The `ai-files` block's manifest (ADR 0029). */
export const aiFilesBlock: BlockOf<
  "ai-files",
  typeof createAiFiles,
  Record<never, never>,
  Record<never, never>,
  "files"
> = defineBlock({
  name: "ai-files",
  sql: ["ai-files"],
  options: { "ai-files": aiFilesSqlOptions },
  provides: { files: (client) => client },
  create: createAiFiles,
  category: "ai",
  entities: {
    ai_document: {
      mutability: "editable",
      emits: { create: false, update: false, delete: false },
    },
  },
  description:
    "Files and documents for AI chats: a private bucket whose policies only accept an upload a reserved record expects, provider file references with expiry, versioned documents with suggested edits, and a purge that hands back the objects to remove.",
});
