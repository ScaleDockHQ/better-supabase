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
    entities: {
      shift: { mutability: "editable", emits: { create: true, update: false } },
      shift_template: { mutability: "editable", emits: { update: false } },
      shift_assignment: {
        mutability: "state-machine",
        emits: { create: true },
      },
      shift_swap: { mutability: "state-machine", emits: { create: false } },
      shift_availability: { mutability: "editable", emits: { update: false } },
    },
    description:
      "Shift templates that generate shifts on weekdays, shifts planned in draft and published per team and location, assignments checked for overlap, approved leave, required qualifications and rest time, open shift requests, swaps between members, availability, a roster, planned hours against contract hours, and time entries from worked shifts.",
  });
