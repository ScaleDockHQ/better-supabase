import type { BlockOf } from "../define-block.ts";
import type { AssignmentEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAssignment } from "./assignment.ts";
import { assignmentEvents } from "./events.ts";
import { assignmentQueueInputSchema } from "./schemas.ts";

/** The `assignment` block's manifest (ADR 0029). */
export const assignmentBlock: BlockOf<
  "assignment",
  typeof createAssignment,
  AssignmentEvents
> = defineBlock({
  name: "assignment",
  sql: ["assignment"],
  events: assignmentEvents,
  schemas: { assignment_queue: { input: assignmentQueueInputSchema } },
  create: createAssignment,
  category: "work",
  entities: {
    assignment_queue: {
      mutability: "editable",
      emits: { update: false, delete: false },
    },
  },
  concerns: ["lifecycle"],
  description:
    "Queues of members that pick an owner for new leads, deals or tickets: round robin or weighted, within a territory written as rule conditions, with a log of every pick.",
});
