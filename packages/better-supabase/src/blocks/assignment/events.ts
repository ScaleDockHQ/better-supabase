import type { AssignmentEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `assignment` block: type to data. */
export type AssignmentEvents = {
  readonly "subject.assigned": AssignmentEventData;
};

/** The `assignment` block's event types, for its manifest and `onBlockEvent`. */
export const assignmentEvents: Events<AssignmentEvents> = defineEvents({
  "subject.assigned": event<AssignmentEventData>(),
});
