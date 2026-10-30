import type {
  ApplicationEventData,
  JobEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `hiring` block: type to data. */
export type HiringEvents = {
  readonly "job_opening.opened": JobEventData;
  readonly "job_opening.closed": JobEventData;
  readonly "application.created": ApplicationEventData;
  readonly "application.hired": ApplicationEventData;
  readonly "application.rejected": ApplicationEventData;
  readonly "application.retracted": ApplicationEventData;
  readonly "scorecard.submitted": ApplicationEventData;
  readonly "interview.scheduled": ApplicationEventData;
};

/** The `hiring` block's event types, for its manifest and `onBlockEvent`. */
export const hiringEvents: Events<HiringEvents> = defineEvents({
  "job_opening.opened": event<JobEventData>(),
  "job_opening.closed": event<JobEventData>(),
  "application.created": event<ApplicationEventData>(),
  "application.hired": event<ApplicationEventData>(),
  "application.rejected": event<ApplicationEventData>(),
  "application.retracted": event<ApplicationEventData>(),
  "scorecard.submitted": event<ApplicationEventData>(),
  "interview.scheduled": event<ApplicationEventData>(),
});
