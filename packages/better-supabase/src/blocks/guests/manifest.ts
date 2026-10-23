import type { BlockOf } from "../define-block.ts";
import type { GuestsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { guestsEvents } from "./events.ts";
import { createGuests } from "./guests.ts";
import { guestsBinding } from "./record-binding.ts";
import { guestGrantSchema, guestInviteSchema } from "./schemas.ts";

/** The `guests` block's manifest (ADR 0029). */
export const guestsBlock: BlockOf<
  "guests",
  typeof createGuests,
  GuestsEvents,
  Record<never, never>,
  never,
  typeof guestsBinding
> = defineBlock({
  name: "guests",
  sql: ["guests"],
  options: {},
  events: guestsEvents,
  schemas: {
    guest: { input: guestInviteSchema },
    guest_grant: { input: guestGrantSchema },
  },
  create: createGuests,
  record: guestsBinding,
  category: "collaboration",
});
