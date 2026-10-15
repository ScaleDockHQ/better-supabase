import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";

/** The `entitlements` block's manifest (ADR 0029). */
export const entitlementsBlock: Block<"entitlements"> = defineBlock({
  name: "entitlements",
  sql: ["entitlements"],
  category: "commerce",
  recipes: ["feature-gate"],
});
