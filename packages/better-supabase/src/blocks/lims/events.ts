import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What every `lims_method.*` event carries. */
export interface LimsMethodEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly key: string;
}

/** What every `lims_sample.*` event carries. */
export interface LimsSampleEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly number: string;
  /** `registered`, `in_testing`, `completed`, `released` or `rejected`. */
  readonly status: string;
}

/** What `lims_result.recorded` and `lims_result.flagged` carry. */
export interface LimsResultEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly sampleId: string;
  readonly methodId: string;
  readonly value: number;
  /** `in_spec` or `out_of_spec`. */
  readonly outcome: string;
  /** The nonconformity case an out of specification result opened. */
  readonly caseId: string | null;
}

/** The events of the `lims` block: type to data. */
export type LimsEvents = {
  readonly "lims_method.created": LimsMethodEventData;
  readonly "lims_method.updated": LimsMethodEventData;
  readonly "lims_method.archived": LimsMethodEventData;
  readonly "lims_sample.registered": LimsSampleEventData;
  readonly "lims_sample.completed": LimsSampleEventData;
  readonly "lims_sample.released": LimsSampleEventData;
  readonly "lims_sample.rejected": LimsSampleEventData;
  readonly "lims_result.recorded": LimsResultEventData;
  readonly "lims_result.flagged": LimsResultEventData;
};

/** The `lims` block's event types, for its manifest and `onBlockEvent`. */
export const limsEvents: Events<LimsEvents> = defineEvents({
  "lims_method.created": event<LimsMethodEventData>(),
  "lims_method.updated": event<LimsMethodEventData>(),
  "lims_method.archived": event<LimsMethodEventData>(),
  "lims_sample.registered": event<LimsSampleEventData>(),
  "lims_sample.completed": event<LimsSampleEventData>(),
  "lims_sample.released": event<LimsSampleEventData>(),
  "lims_sample.rejected": event<LimsSampleEventData>(),
  "lims_result.recorded": event<LimsResultEventData>(),
  "lims_result.flagged": event<LimsResultEventData>(),
});
