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
  category: "crm",
});
