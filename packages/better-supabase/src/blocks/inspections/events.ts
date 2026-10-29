import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** A program was saved or changed state. */
export interface InspectionProgramEventData {
  readonly organizationId: string;
  readonly programId: string;
}

/** An inspection was scheduled, changed or moved. */
export interface InspectionEventData {
  readonly organizationId: string;
  readonly inspectionId: string;
  readonly number: string;
}

/** An inspection changed. */
export interface InspectionUpdatedEventData extends InspectionEventData {
  readonly changed: readonly string[];
}

/** A finding was added or changed. */
export interface InspectionFindingEventData {
  readonly organizationId: string;
  readonly inspectionId: string;
  readonly findingId: string;
  readonly type?: string;
  readonly caseId?: string;
}

/** The events of the `inspections` block. */
export type InspectionsEvents = {
  readonly "inspection_program.created": InspectionProgramEventData;
  readonly "inspection_program.updated": InspectionProgramEventData;
  readonly "inspection_program.approved": InspectionProgramEventData;
  readonly "inspection_program.closed": InspectionProgramEventData;
  readonly "inspection.scheduled": InspectionEventData;
  readonly "inspection.updated": InspectionUpdatedEventData;
  readonly "inspection.started": InspectionEventData;
  readonly "inspection.completed": InspectionEventData;
  readonly "inspection.closed": InspectionEventData;
  readonly "inspection.cancelled": InspectionEventData;
  readonly "inspection_finding.created": InspectionFindingEventData;
  readonly "inspection_finding.updated": InspectionFindingEventData;
  readonly "inspection_finding.deleted": InspectionFindingEventData;
  readonly "inspection_finding.case_raised": InspectionFindingEventData;
};

export const inspectionsEvents: Events<InspectionsEvents> = defineEvents({
  "inspection_program.created": event<InspectionProgramEventData>(),
  "inspection_program.updated": event<InspectionProgramEventData>(),
  "inspection_program.approved": event<InspectionProgramEventData>(),
  "inspection_program.closed": event<InspectionProgramEventData>(),
  "inspection.scheduled": event<InspectionEventData>(),
  "inspection.updated": event<InspectionUpdatedEventData>(),
  "inspection.started": event<InspectionEventData>(),
  "inspection.completed": event<InspectionEventData>(),
  "inspection.closed": event<InspectionEventData>(),
  "inspection.cancelled": event<InspectionEventData>(),
  "inspection_finding.created": event<InspectionFindingEventData>(),
  "inspection_finding.updated": event<InspectionFindingEventData>(),
  "inspection_finding.deleted": event<InspectionFindingEventData>(),
  "inspection_finding.case_raised": event<InspectionFindingEventData>(),
});
