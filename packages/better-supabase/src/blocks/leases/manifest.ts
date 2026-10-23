import type { BlockOf } from "../define-block.ts";
import type { LeasesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { leasesEvents } from "./events.ts";
import { createLeases } from "./leases.ts";
import { leasesSqlOptions } from "./options.ts";
import { leasesBinding } from "./record-binding.ts";
import { leaseInputSchema, maintenanceRequestInputSchema } from "./schemas.ts";

/** The `leases` block's manifest (ADR 0029). */
export const leasesBlock: BlockOf<
  "leases",
  typeof createLeases,
  LeasesEvents,
  Record<never, never>,
  never,
  typeof leasesBinding
> = defineBlock({
  name: "leases",
  sql: ["leases"],
  options: { leases: leasesSqlOptions },
  events: leasesEvents,
  schemas: {
    lease: { input: leaseInputSchema },
    maintenance_request: { input: maintenanceRequestInputSchema },
  },
  create: createLeases,
  record: leasesBinding,
  category: "commerce",
});
