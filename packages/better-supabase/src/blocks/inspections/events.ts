import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What every `inspection_program.*` event carries. */
export interface InspectionProgramEventData {
  readonly organizationId: string;
  /** The programme. */
  readonly id: string;
  readonly name: string;
  /** Its status after the change. */
  readonly status: string;
}

/** What every `inspection.*` event carries. */
export interface InspectionEventData {
  readonly organizationId: string;
  /** The inspection. */
  readonly id: string;
  /** Its number, such as `AUD-2026-001`. */
  readonly number: string;
  /** One of `options.kinds`. */
  readonly kind: string;
  readonly title: string;
  /** Its status after the change. */
  readonly status: string;
}

/** `inspection.cancelled`. */
export interface InspectionCancelledEventData extends InspectionEventData {
  readonly reason: string | null;
}

/** What every `inspection_finding.*` event carries. */
export interface InspectionFindingEventData {
  readonly organizationId: string;
  /** The finding. */
  readonly id: string;
  readonly inspectionId: string;
  /** 1, 2, 3 within the inspection. */
  readonly number: number;
  /** One of `options.findingTypes`. */
  readonly type: string;
  readonly title: string;
}

/** `inspection_finding.case_raised`: a case was opened for the finding. */
export interface InspectionFindingCaseRaisedEventData extends InspectionFindingEventData {
  readonly caseId: string;
}

/** The events of the `inspections` block: type to data. */
export type InspectionsEvents = {
  readonly "inspection_program.created": InspectionProgramEventData;
  readonly "inspection_program.updated": InspectionProgramEventData;
  readonly "inspection_program.approved": InspectionProgramEventData;
  readonly "inspection_program.closed": InspectionProgramEventData;
  readonly "inspection.scheduled": InspectionEventData;
  readonly "inspection.updated": InspectionEventData;
  readonly "inspection.started": InspectionEventData;
  readonly "inspection.completed": InspectionEventData;
  readonly "inspection.closed": InspectionEventData;
  readonly "inspection.cancelled": InspectionCancelledEventData;
  readonly "inspection_finding.created": InspectionFindingEventData;
  readonly "inspection_finding.updated": InspectionFindingEventData;
  readonly "inspection_finding.deleted": InspectionFindingEventData;
  readonly "inspection_finding.case_raised": InspectionFindingCaseRaisedEventData;
};

/** The `inspections` block's event types, for its manifest and `onBlockEvent`. */
export const inspectionsEvents: Events<InspectionsEvents> = defineEvents({
  "inspection_program.created": event<InspectionProgramEventData>(),
  "inspection_program.updated": event<InspectionProgramEventData>(),
  "inspection_program.approved": event<InspectionProgramEventData>(),
  "inspection_program.closed": event<InspectionProgramEventData>(),
  "inspection.scheduled": event<InspectionEventData>(),
  "inspection.updated": event<InspectionEventData>(),
  "inspection.started": event<InspectionEventData>(),
  "inspection.completed": event<InspectionEventData>(),
  "inspection.closed": event<InspectionEventData>(),
  "inspection.cancelled": event<InspectionCancelledEventData>(),
  "inspection_finding.created": event<InspectionFindingEventData>(),
  "inspection_finding.updated": event<InspectionFindingEventData>(),
  "inspection_finding.deleted": event<InspectionFindingEventData>(),
  "inspection_finding.case_raised":
    event<InspectionFindingCaseRaisedEventData>(),
});
