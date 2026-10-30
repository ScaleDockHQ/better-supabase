import type { BlockOf } from "../define-block.ts";
import type { ShiftsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { shiftsEvents } from "./events.ts";
import { shiftsSqlOptions } from "./options.ts";
import {
  shiftAvailabilityInputSchema,
  shiftInputSchema,
  shiftTemplateInputSchema,
} from "./schemas.ts";
import { createShifts } from "./shifts.ts";

/** The `shifts` block's manifest (ADR 0029). */
export const shiftsBlock: BlockOf<"shifts", typeof createShifts, ShiftsEvents> =
  defineBlock({
    name: "shifts",
    sql: ["shifts"],
    options: { shifts: shiftsSqlOptions },
    events: shiftsEvents,
    schemas: {
      shift: { input: shiftInputSchema },
      shift_template: { input: shiftTemplateInputSchema },
      shift_availability: { input: shiftAvailabilityInputSchema },
    },
    create: createShifts,
    recipes: ["roster-board"],
    category: "people",
  });
