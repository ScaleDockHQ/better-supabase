import type { WorkItemEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `tasks` block: type to data. */
export type TasksEvents = {
  readonly "task.created": WorkItemEventData;
  readonly "task.updated": WorkItemEventData;
  readonly "task.assigned": WorkItemEventData;
  readonly "task.closed": WorkItemEventData;
  readonly "task.reopened": WorkItemEventData;
  readonly "task.archived": WorkItemEventData;
  readonly "task.deleted": WorkItemEventData;
};

/** The `tasks` block's event types, for its manifest and `onBlockEvent`. */
export const tasksEvents: Events<TasksEvents> = defineEvents({
  "task.created": event<WorkItemEventData>(),
  "task.updated": event<WorkItemEventData>(),
  "task.assigned": event<WorkItemEventData>(),
  "task.closed": event<WorkItemEventData>(),
  "task.reopened": event<WorkItemEventData>(),
  "task.archived": event<WorkItemEventData>(),
  "task.deleted": event<WorkItemEventData>(),
});
