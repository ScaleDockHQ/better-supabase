import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** A case was opened. */
export interface CaseCreatedEventData {
  readonly organizationId: string;
  readonly caseId: string;
  readonly kind: string;
  readonly number: string;
}

/** A case changed. */
export interface CaseUpdatedEventData extends CaseCreatedEventData {
  readonly changed: readonly string[];
}

/** A root cause was recorded. */
export type CaseRootCauseRecordedEventData = CaseCreatedEventData;

/** An action was added. */
export interface CaseActionAddedEventData {
  readonly organizationId: string;
  readonly caseId: string;
  readonly actionId: string;
  readonly type: string;
}

/** An action was completed. */
export interface CaseActionCompletedEventData {
  readonly organizationId: string;
  readonly caseId: string;
  readonly actionId: string;
}

/** Effectiveness was recorded. */
export interface CaseEffectivenessRecordedEventData
  extends CaseCreatedEventData {
  readonly effective: boolean;
}

/** A case was closed, reopened or cancelled. */
export type CaseClosedEventData = CaseCreatedEventData;

/** A case kind was saved. */
export interface CaseKindSavedEventData {
  readonly organizationId: string;
  readonly kindId: string;
  readonly key: string;
}

/** The events of the `cases` block. */
export type CasesEvents = {
  readonly "case.created": CaseCreatedEventData;
  readonly "case.updated": CaseUpdatedEventData;
  readonly "case.root_cause_recorded": CaseRootCauseRecordedEventData;
  readonly "case.action_added": CaseActionAddedEventData;
  readonly "case.action_completed": CaseActionCompletedEventData;
  readonly "case.effectiveness_recorded": CaseEffectivenessRecordedEventData;
  readonly "case.closed": CaseClosedEventData;
  readonly "case.reopened": CaseClosedEventData;
  readonly "case.cancelled": CaseClosedEventData;
  readonly "case_kind.created": CaseKindSavedEventData;
  readonly "case_kind.updated": CaseKindSavedEventData;
};

export const casesEvents: Events<CasesEvents> = defineEvents({
  "case.created": event<CaseCreatedEventData>(),
  "case.updated": event<CaseUpdatedEventData>(),
  "case.root_cause_recorded": event<CaseRootCauseRecordedEventData>(),
  "case.action_added": event<CaseActionAddedEventData>(),
  "case.action_completed": event<CaseActionCompletedEventData>(),
  "case.effectiveness_recorded": event<CaseEffectivenessRecordedEventData>(),
  "case.closed": event<CaseClosedEventData>(),
  "case.reopened": event<CaseClosedEventData>(),
  "case.cancelled": event<CaseClosedEventData>(),
  "case_kind.created": event<CaseKindSavedEventData>(),
  "case_kind.updated": event<CaseKindSavedEventData>(),
});
