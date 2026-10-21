import type { WorkflowEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `workflow-builder` block: type to data. */
export type WorkflowBuilderEvents = {
  readonly "workflow.published": WorkflowEventData;
  readonly "workflow_alert.triggered": WorkflowEventData;
};

/**
 * The `workflow-builder` block's event types, for its manifest and
 * `onBlockEvent`.
 */
export const workflowBuilderEvents: Events<WorkflowBuilderEvents> =
  defineEvents({
    "workflow.published": event<WorkflowEventData>(),
    "workflow_alert.triggered": event<WorkflowEventData>(),
  });
