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
  entities: { entitlement: { mutability: "read-only" } },
  description:
    "Active Stripe entitlements per tenant from the Stripe Sync Engine, feature_claims() for the access token hook, and has_entitlement() and tenant_ids_with_entitlement() for RLS.",
  recipes: ["feature-gate"],
});
