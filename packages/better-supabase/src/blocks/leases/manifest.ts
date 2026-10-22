import type { BlockOf } from "../define-block.ts";
import type { LeasesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { leasesEvents } from "./events.ts";
import { createLeases } from "./leases.ts";
import { leaseInputSchema, maintenanceRequestInputSchema } from "./schemas.ts";
import { leasesSection } from "./section.ts";

/** The `leases` block's manifest (ADR 0029). */
export const leasesBlock: BlockOf<
  "leases",
  typeof createLeases,
  LeasesEvents,
  Record<never, never>,
  never,
  { readonly leases: typeof leasesSection }
> = defineBlock({
  name: "leases",
  sql: ["leases"],
  options: {},
  events: leasesEvents,
  schemas: {
    lease: { input: leaseInputSchema },
    maintenance_request: { input: maintenanceRequestInputSchema },
  },
  create: createLeases,
  sections: { leases: leasesSection },
  category: "commerce",
});
