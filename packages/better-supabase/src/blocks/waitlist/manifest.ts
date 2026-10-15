import type { BlockOf } from "../define-block.ts";
import type { WaitlistEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { waitlistEvents } from "./events.ts";
import { createWaitlist } from "./waitlist.ts";

/** The `waitlist` block's manifest (ADR 0029). */
export const waitlistBlock: BlockOf<
  "waitlist",
  typeof createWaitlist,
  WaitlistEvents
> = defineBlock({
  name: "waitlist",
  sql: ["waitlist"],
  options: {
    waitlist: optionKeys(["defaultRole", "codeField", "roles"]),
  },
  events: waitlistEvents,
  create: createWaitlist,
  category: "operations",
});
