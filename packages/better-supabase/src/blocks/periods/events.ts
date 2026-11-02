import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What every `period.*` event carries. */
export interface PeriodEventData {
  readonly organizationId: string;
  readonly id: string;
  /** The kind, such as `fiscal_period` or `leave_year`. */
  readonly kind: string;
  /** The first day, as an ISO date. */
  readonly startsOn: string;
  /** The last day, as an ISO date. */
  readonly endsOn: string;
  /** `open`, `locked` or `closed`. */
  readonly status: string;
}

/** The events of the `periods` block: type to data. */
export type PeriodsEvents = {
  readonly "period.created": PeriodEventData;
  readonly "period.locked": PeriodEventData;
  readonly "period.closed": PeriodEventData;
  readonly "period.reopened": PeriodEventData;
};

/** The `periods` block's event types, for its manifest and `onBlockEvent`. */
export const periodsEvents: Events<PeriodsEvents> = defineEvents({
  "period.created": event<PeriodEventData>(),
  "period.locked": event<PeriodEventData>(),
  "period.closed": event<PeriodEventData>(),
  "period.reopened": event<PeriodEventData>(),
});
