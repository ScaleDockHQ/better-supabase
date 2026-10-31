import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What every `appraisal_cycle.*` event carries. */
export interface AppraisalCycleEventData {
  readonly organizationId: string;
  /** The cycle. */
  readonly id: string;
  readonly name: string;
  /** `draft`, `open` or `closed`. */
  readonly status: string;
}

/** What the `appraisal.*` events carry. */
export interface AppraisalEventData {
  readonly organizationId: string;
  /** The appraisal. */
  readonly id: string;
  readonly cycleId: string;
  readonly subjectUserId: string;
  readonly status: string;
}

/** `appraisal.calibrated` and `appraisal.finalized`. */
export interface AppraisalRatedEventData extends AppraisalEventData {
  /** The rating the appraisal ends with, as a decimal string. */
  readonly rating: string | null;
}

/** `appraisal_review.submitted`. */
export interface AppraisalReviewEventData {
  readonly organizationId: string;
  /** The review. */
  readonly id: string;
  readonly appraisalId: string;
  readonly reviewerId: string;
  /** `self`, `peer` or `manager`. */
  readonly kind: string;
  /** 1 to 5. */
  readonly rating: number;
}

/** The events of the `appraisals` block: type to data. */
export type AppraisalsEvents = {
  readonly "appraisal_cycle.created": AppraisalCycleEventData;
  readonly "appraisal_cycle.opened": AppraisalCycleEventData;
  readonly "appraisal_cycle.closed": AppraisalCycleEventData;
  readonly "appraisal.created": AppraisalEventData;
  readonly "appraisal.calibrated": AppraisalRatedEventData;
  readonly "appraisal.finalized": AppraisalRatedEventData;
  readonly "appraisal_review.submitted": AppraisalReviewEventData;
};

/** The `appraisals` block's event types, for its manifest and `onBlockEvent`. */
export const appraisalsEvents: Events<AppraisalsEvents> = defineEvents({
  "appraisal_cycle.created": event<AppraisalCycleEventData>(),
  "appraisal_cycle.opened": event<AppraisalCycleEventData>(),
  "appraisal_cycle.closed": event<AppraisalCycleEventData>(),
  "appraisal.created": event<AppraisalEventData>(),
  "appraisal.calibrated": event<AppraisalRatedEventData>(),
  "appraisal.finalized": event<AppraisalRatedEventData>(),
  "appraisal_review.submitted": event<AppraisalReviewEventData>(),
});
