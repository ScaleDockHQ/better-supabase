import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createdBySqlOptions } from "./options.ts";

/** The `created-by` block's manifest (ADR 0029). */
export const createdByBlock: Block<"created-by"> = defineBlock({
  name: "created-by",
  sql: ["created-by"],
  options: { "created-by": createdBySqlOptions },
  category: "identity",
  extension: "createdByExtension",
});
