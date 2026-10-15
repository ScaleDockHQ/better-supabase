import type {
  PipelineEventData,
  PipelineStageEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `pipelines` block: type to data. */
export type PipelinesEvents = {
  readonly "pipeline.created": PipelineEventData;
  readonly "pipeline.updated": PipelineEventData;
  readonly "pipeline.archived": PipelineEventData;
  readonly "pipeline_stage.saved": PipelineEventData;
  readonly "pipeline_stage.archived": PipelineEventData;
  readonly "pipeline.stage_changed": PipelineStageEventData;
};

/** The `pipelines` block's event types, for its manifest and `onBlockEvent`. */
export const pipelinesEvents: Events<PipelinesEvents> = defineEvents({
  "pipeline.created": event<PipelineEventData>(),
  "pipeline.updated": event<PipelineEventData>(),
  "pipeline.archived": event<PipelineEventData>(),
  "pipeline_stage.saved": event<PipelineEventData>(),
  "pipeline_stage.archived": event<PipelineEventData>(),
  "pipeline.stage_changed": event<PipelineStageEventData>(),
});
