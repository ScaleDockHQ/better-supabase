import type { BlockOf } from "../define-block.ts";
import type { GuestsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { guestsEvents } from "./events.ts";
import { createGuests } from "./guests.ts";
import { guestListSurface } from "./lists.ts";
import { guestsSqlOptions } from "./options.ts";
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
  options: { guests: guestsSqlOptions },
  events: guestsEvents,
  schemas: {
    guest: { input: guestInviteSchema },
    guest_grant: { input: guestGrantSchema },
  },
  create: createGuests,
  record: guestsBinding,
  category: "collaboration",
  entities: {
    guest: { ...guestListSurface, mutability: "state-machine" },
    guest_grant: { mutability: "state-machine", emits: { create: true } },
  },
  concerns: ["lifecycle"],
  description:
    "People outside the organization (clients, contractors) invited by email who read, comment on and upload to the records they are granted, and see the invoices and bookings of the party they act for. Never members, never through an authorization library.",
});
