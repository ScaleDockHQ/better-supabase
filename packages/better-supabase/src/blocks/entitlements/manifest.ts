import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createEntitlements } from "./entitlements.ts";

/** The `entitlements` block's manifest (ADR 0029). */
export const entitlementsBlock: BlockOf<
  "entitlements",
  typeof createEntitlements
> = defineBlock({
  name: "entitlements",
  sql: ["entitlements"],
  create: createEntitlements,
  category: "commerce",
  recipes: ["feature-gate"],
});
