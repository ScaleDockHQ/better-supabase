import type { WorkItemEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `tasks` block: type to data. */
export type TasksEvents = {
  readonly "work_item.created": WorkItemEventData;
  readonly "work_item.updated": WorkItemEventData;
  readonly "work_item.assigned": WorkItemEventData;
  readonly "work_item.closed": WorkItemEventData;
  readonly "work_item.reopened": WorkItemEventData;
  readonly "work_item.archived": WorkItemEventData;
  readonly "work_item.deleted": WorkItemEventData;
};

/** The `tasks` block's event types, for its manifest and `onBlockEvent`. */
export const tasksEvents: Events<TasksEvents> = defineEvents({
  "work_item.created": event<WorkItemEventData>(),
  "work_item.updated": event<WorkItemEventData>(),
  "work_item.assigned": event<WorkItemEventData>(),
  "work_item.closed": event<WorkItemEventData>(),
  "work_item.reopened": event<WorkItemEventData>(),
  "work_item.archived": event<WorkItemEventData>(),
  "work_item.deleted": event<WorkItemEventData>(),
});
