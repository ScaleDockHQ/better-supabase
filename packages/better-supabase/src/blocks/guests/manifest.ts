import type { BlockOf } from "../define-block.ts";
import type { GuestsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { guestsEvents } from "./events.ts";
import { createGuests } from "./guests.ts";
import { guestGrantSchema, guestInviteSchema } from "./schemas.ts";
import { guestsSection } from "./section.ts";

/** The `guests` block's manifest (ADR 0029). */
export const guestsBlock: BlockOf<
  "guests",
  typeof createGuests,
  GuestsEvents,
  Record<never, never>,
  never,
  { readonly guests: typeof guestsSection }
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
  sections: { guests: guestsSection },
  category: "collaboration",
});
