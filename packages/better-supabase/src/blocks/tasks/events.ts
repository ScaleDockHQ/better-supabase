import type { TaskEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `tasks` block: type to data. */
export type TasksEvents = {
  readonly "task.created": TaskEventData;
  readonly "task.updated": TaskEventData;
  readonly "task.assigned": TaskEventData;
  readonly "task.closed": TaskEventData;
  readonly "task.reopened": TaskEventData;
  readonly "task.archived": TaskEventData;
  readonly "task.restored": TaskEventData;
  readonly "task.deleted": TaskEventData;
  readonly "task.unblocked": TaskEventData;
  readonly "task.claimed": TaskEventData;
  readonly "task.released": TaskEventData;
  readonly "task.claim_expired": TaskEventData;
  readonly "task.failed": TaskEventData;
  readonly "task.delegated": TaskEventData;
  readonly "task.held": TaskEventData;
  readonly "task.hold_released": TaskEventData;
};

/** The `tasks` block's event types, for its manifest and `onBlockEvent`. */
export const tasksEvents: Events<TasksEvents> = defineEvents({
  "task.created": event<TaskEventData>(),
  "task.updated": event<TaskEventData>(),
  "task.assigned": event<TaskEventData>(),
  "task.closed": event<TaskEventData>(),
  "task.reopened": event<TaskEventData>(),
  "task.archived": event<TaskEventData>(),
  "task.restored": event<TaskEventData>(),
  "task.deleted": event<TaskEventData>(),
  "task.unblocked": event<TaskEventData>(),
  "task.claimed": event<TaskEventData>(),
  "task.released": event<TaskEventData>(),
  "task.claim_expired": event<TaskEventData>(),
  "task.failed": event<TaskEventData>(),
  "task.delegated": event<TaskEventData>(),
  "task.held": event<TaskEventData>(),
  "task.hold_released": event<TaskEventData>(),
});
