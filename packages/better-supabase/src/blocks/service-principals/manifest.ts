import type { BlockOf } from "../define-block.ts";
import type { ServicePrincipalsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { servicePrincipalsEvents } from "./events.ts";
import { createServicePrincipals } from "./service-principals.ts";

/** The `service-principals` block's manifest (ADR 0029). */
export const servicePrincipalsBlock: BlockOf<
  "service-principals",
  typeof createServicePrincipals,
  ServicePrincipalsEvents
> = defineBlock({
  name: "service-principals",
  sql: ["service-principals"],
  events: servicePrincipalsEvents,
  create: createServicePrincipals,
  category: "platform",
});
