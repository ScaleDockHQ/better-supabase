import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { reservedSlugsSqlOptions } from "./options.ts";

/** The `reserved-slugs` block's manifest (ADR 0029). */
export const reservedSlugsBlock: Block<"reserved-slugs"> = defineBlock({
  name: "reserved-slugs",
  sql: ["reserved-slugs"],
  options: { "reserved-slugs": reservedSlugsSqlOptions },
  category: "tenancy",
  entities: { reserved_slug: { mutability: "read-only" } },
  description:
    "A slug format and length check and a list of reserved words (admin, api, www, ...), enforced by a trigger.",
  recipes: ["workspace-url-field"],
});
