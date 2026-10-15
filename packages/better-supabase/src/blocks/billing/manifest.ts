import type { BlockOf } from "../define-block.ts";
import type { BillingEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createBilling } from "./billing.ts";
import { billingEvents } from "./events.ts";

/** The `billing` block's manifest (ADR 0029). */
export const billingBlock: BlockOf<
  "billing",
  typeof createBilling,
  BillingEvents
> = defineBlock({
  name: "billing",
  sql: ["billing"],
  options: {
    billing: optionKeys(["seatRoles", "plans", "tenantKey"]),
  },
  events: billingEvents,
  create: createBilling,
  category: "commerce",
  recipes: ["plan-picker"],
});
