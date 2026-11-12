import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createdBySqlOptions } from "./options.ts";

/** The `created-by` block's manifest (ADR 0029). */
export const createdByBlock: Block<"created-by"> = defineBlock({
  name: "created-by",
  sql: ["created-by"],
  options: { "created-by": createdBySqlOptions },
  category: "identity",
  entities: { created_by: { mutability: "read-only" } },
  description:
    "Sets created_by on insert and updated_by on every write from auth.uid(); an update keeps created_by and the impersonation stamp. Service writes keep the values they send.",
  extension: "createdByExtension",
});
