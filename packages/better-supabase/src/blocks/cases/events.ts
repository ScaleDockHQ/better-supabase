import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The `case_kind.*` events. */
export interface CaseKindEventData {
  readonly organizationId: string;
  readonly caseKindId: string;
  readonly key: string;
  readonly name: string;
  readonly prefix: string;
}

/** What every `case.*` and `case_action.*` event carries. */
export interface CaseEventData {
  readonly organizationId: string;
  readonly caseId: string;
  /** The kind's key, such as `complaint`. */
  readonly kind: string;
  /** Such as `CMP-2026-0001`. */
  readonly number: string;
  readonly title: string;
  /** `open`, `closed` or `canceled`, after the change. */
  readonly status: string;
}

/** `case.updated`: the keys `update` changed. */
export interface CaseUpdatedEventData extends CaseEventData {
  readonly changed: readonly string[];
}

/** `case.root_cause_recorded`. */
export interface CaseRootCauseRecordedEventData extends CaseEventData {
  readonly rootCause: string;
}

/** `case_action.created`. */
export interface CaseActionCreatedEventData extends CaseEventData {
  readonly actionId: string;
  readonly taskId: string;
  readonly type: string;
  readonly required: boolean;
}

/** `case_action.deleted`. */
export interface CaseActionDeletedEventData extends CaseEventData {
  readonly actionId: string;
  readonly taskId: string;
  readonly type: string;
}

/** `case.effectiveness_recorded`. */
export interface CaseEffectivenessRecordedEventData extends CaseEventData {
  readonly effective: boolean;
  readonly note: string | null;
}

/** `case.effectiveness_date_reached`: the effectiveness check is due. */
export interface CaseEffectivenessDateReachedEventData extends CaseEventData {
  readonly ownerId: string | null;
  /** `YYYY-MM-DD`. */
  readonly effectivenessDueOn: string;
}

/** `case.closed`. */
export interface CaseClosedEventData extends CaseEventData {
  readonly note: string | null;
}

/** `case.reopened` and `case.cancelled`. */
export interface CaseReasonEventData extends CaseEventData {
  readonly reason: string | null;
}

/** The events of the `cases` block: type to data. */
export type CasesEvents = {
  readonly "case_kind.created": CaseKindEventData;
  readonly "case_kind.updated": CaseKindEventData;
  readonly "case_kind.archived": CaseKindEventData;
  readonly "case.created": CaseEventData;
  readonly "case.updated": CaseUpdatedEventData;
  readonly "case.root_cause_recorded": CaseRootCauseRecordedEventData;
  readonly "case_action.created": CaseActionCreatedEventData;
  readonly "case_action.deleted": CaseActionDeletedEventData;
  readonly "case.effectiveness_recorded": CaseEffectivenessRecordedEventData;
  readonly "case.effectiveness_date_reached": CaseEffectivenessDateReachedEventData;
  readonly "case.closed": CaseClosedEventData;
  readonly "case.reopened": CaseReasonEventData;
  readonly "case.cancelled": CaseReasonEventData;
};

/** The `cases` block's event types, for its manifest and `onBlockEvent`. */
export const casesEvents: Events<CasesEvents> = defineEvents({
  "case_kind.created": event<CaseKindEventData>(),
  "case_kind.updated": event<CaseKindEventData>(),
  "case_kind.archived": event<CaseKindEventData>(),
  "case.created": event<CaseEventData>(),
  "case.updated": event<CaseUpdatedEventData>(),
  "case.root_cause_recorded": event<CaseRootCauseRecordedEventData>(),
  "case_action.created": event<CaseActionCreatedEventData>(),
  "case_action.deleted": event<CaseActionDeletedEventData>(),
  "case.effectiveness_recorded": event<CaseEffectivenessRecordedEventData>(),
  "case.effectiveness_date_reached":
    event<CaseEffectivenessDateReachedEventData>(),
  "case.closed": event<CaseClosedEventData>(),
  "case.reopened": event<CaseReasonEventData>(),
  "case.cancelled": event<CaseReasonEventData>(),
});
