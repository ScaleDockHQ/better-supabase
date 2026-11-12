import type { BlockOf } from "../define-block.ts";
import type { AcknowledgementsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAcknowledgements } from "./acknowledgements.ts";
import { acknowledgementsEvents } from "./events.ts";

/** The `acknowledgements` block's manifest (ADR 0029). */
export const acknowledgementsBlock: BlockOf<
  "acknowledgements",
  typeof createAcknowledgements,
  AcknowledgementsEvents
> = defineBlock({
  name: "acknowledgements",
  sql: ["acknowledgements"],
  events: acknowledgementsEvents,
  create: createAcknowledgements,
  category: "collaboration",
  entities: {
    acknowledgement: { mutability: "state-machine", emits: { create: true } },
    acknowledgement_assignment: {
      mutability: "append-only",
      emits: { create: true, delete: true },
    },
  },
  description:
    "Members confirm they read the current version of a record: assignments to a member, a team or a role, a due date per assignment, a click or a completed signature, and a reminder once a version is overdue.",
  recipes: ["acknowledgement-inbox"],
});
