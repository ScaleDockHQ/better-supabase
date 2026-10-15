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
  options: {
    "ai-files": aiFilesSqlOptions,
  },
  provides: {
    files: (client) => client,
  },
  create: createAiFiles,
  category: "ai",
});
