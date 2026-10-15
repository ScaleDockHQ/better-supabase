import type { Events, WorkflowRunEventData } from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `workflows` block: type to data. */
export type WorkflowsEvents = {
  readonly "workflow_run.completed": WorkflowRunEventData;
  readonly "workflow_run.failed": WorkflowRunEventData;
  readonly "workflow_run.cancelled": WorkflowRunEventData;
};

/** The `workflows` block's event types, for its manifest and `onBlockEvent`. */
export const workflowsEvents: Events<WorkflowsEvents> = defineEvents({
  "workflow_run.completed": event<WorkflowRunEventData>(),
  "workflow_run.failed": event<WorkflowRunEventData>(),
  "workflow_run.cancelled": event<WorkflowRunEventData>(),
});
