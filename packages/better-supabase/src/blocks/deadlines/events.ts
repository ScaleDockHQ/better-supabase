import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What every `deadline.*` event carries. */
export interface DeadlineEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** The group of the rule set version the deadline belongs to. */
  readonly groupKey: string;
  /** The rule that applied; null when none did. */
  readonly ruleKey?: string | null;
  /** `YYYY-MM` for one month of a periodic rule. */
  readonly period?: string | null;
  /**
   * `due`, `unknown`, `pending`, `undated`, `not_covered`, `not_applicable`,
   * `not_required` or `barred`.
   */
  readonly result: string;
  /** The due date as an ISO date; set only while the result is `due`. */
  readonly dueOn?: string | null;
  /** A date or result a missing answer could still change. */
  readonly provisional: boolean;
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
