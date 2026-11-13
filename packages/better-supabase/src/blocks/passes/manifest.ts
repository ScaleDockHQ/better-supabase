import type { BlockOf } from "../define-block.ts";
import type { PassesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { passesEvents } from "./events.ts";
import { passesSqlOptions } from "./options.ts";
import { createPasses } from "./passes.ts";
import { passesBinding } from "./record-binding.ts";
import { passInputSchema } from "./schemas.ts";

/** The `passes` block's manifest (ADR 0029). */
export const passesBlock: BlockOf<
  "passes",
  typeof createPasses,
  PassesEvents,
  Record<never, never>,
  never,
  typeof passesBinding
> = defineBlock({
  name: "passes",
  sql: ["passes"],
  options: { passes: passesSqlOptions },
  events: passesEvents,
  schemas: { pass: { input: passInputSchema } },
  create: createPasses,
  record: passesBinding,
  category: "scheduling",
  entities: {
    pass: { mutability: "state-machine", emits: { create: false } },
    pass_check_in: { mutability: "read-only" },
  },
  concerns: ["lifecycle"],
  description:
    "Admission passes on QR codes and NFC tags, signed with the signing-keys block: a ticket for a booking or a pass with a number of uses for a resource, a log of every scan, class credits that pay for bookings and come back on an early cancellation, and drop-ins counted against the resource's capacity with its bookings.",
});
