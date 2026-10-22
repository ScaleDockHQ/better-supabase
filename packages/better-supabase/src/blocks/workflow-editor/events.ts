import type { WorkflowEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `workflow-editor` block: type to data. */
export type WorkflowEditorEvents = {
  readonly "workflow.published": WorkflowEventData;
  readonly "workflow_alert.triggered": WorkflowEventData;
};

/**
 * The `workflow-editor` block's event types, for its manifest and
 * `onBlockEvent`.
 */
export const workflowEditorEvents: Events<WorkflowEditorEvents> = defineEvents({
  "workflow.published": event<WorkflowEventData>(),
  "workflow_alert.triggered": event<WorkflowEventData>(),
});
