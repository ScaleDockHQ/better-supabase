import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What every `deadline.*` event carries. */
export interface DeadlineEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly ruleKey: string;
  /** `due` or `unknown`. */
  readonly result: string;
  /** The due date as an ISO date; absent while the result is `unknown`. */
  readonly dueOn?: string | null;
}

/** The events of the `deadlines` block: type to data. */
export type DeadlinesEvents = {
  readonly "deadline.computed": DeadlineEventData;
  readonly "deadline.satisfied": DeadlineEventData;
};

/** The `deadlines` block's event types, for its manifest and `onBlockEvent`. */
export const deadlinesEvents: Events<DeadlinesEvents> = defineEvents({
  "deadline.computed": event<DeadlineEventData>(),
  "deadline.satisfied": event<DeadlineEventData>(),
});
