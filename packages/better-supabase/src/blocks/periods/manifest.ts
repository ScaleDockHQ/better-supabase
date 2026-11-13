import type { BlockOf } from "../define-block.ts";
import type { PeriodsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { periodsEvents } from "./events.ts";
import { createPeriods } from "./periods.ts";

/** The `periods` block's manifest (ADR 0197). */
export const periodsBlock: BlockOf<
  "periods",
  typeof createPeriods,
  PeriodsEvents
> = defineBlock({
  name: "periods",
  sql: ["periods"],
  events: periodsEvents,
  schemas: {},
  create: createPeriods,
  recipes: [],
  category: "commerce",
  entities: {
    period: {
      mutability: "state-machine",
      emits: { create: true },
      permissions: {
        read: "periods.read",
        create: "periods.write",
        manage: "periods.manage",
      },
    },
  },
  description:
    "Dated periods per kind with open, locked and closed states, a lookup by date and a close protocol where blocks contribute close blockers and an on-close step.",
});
