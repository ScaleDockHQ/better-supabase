import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `control.created` and `control.updated`: a control was created or changed. */
export interface ControlSavedEventData {
  readonly organizationId: string;
  readonly controlId: string;
  readonly frameworkId: string;
  readonly code: string;
}

/** `control.evidence_added`: evidence was collected for a control. */
export interface ControlEvidenceAddedEventData {
  readonly organizationId: string;
  readonly controlId: string;
  readonly evidenceId: string;
  /** The recurring task the evidence answers, if any. */
  readonly evidenceTaskId: string | null;
}

/** `evidence_task.missed`: a recurring evidence task passed its due date. */
export interface EvidenceTaskMissedEventData {
  readonly organizationId: string;
  readonly evidenceTaskId: string;
  readonly controlId: string;
  readonly assigneeId: string | null;
  /** `YYYY-MM-DD`. */
  readonly dueOn: string;
}

/** `compliance_policy.published`: a policy has a new current version. */
export interface PolicyPublishedEventData {
  readonly organizationId: string;
  readonly policyId: string;
  readonly versionId: string;
  readonly number: number;
}

/** The events of the `compliance` block: type to data. */
export type ComplianceEvents = {
  readonly "control.created": ControlSavedEventData;
  readonly "control.updated": ControlSavedEventData;
  readonly "control.evidence_added": ControlEvidenceAddedEventData;
  readonly "evidence_task.missed": EvidenceTaskMissedEventData;
  readonly "compliance_policy.published": PolicyPublishedEventData;
};

/** The `compliance` block's event types, for its manifest and `onBlockEvent`. */
export const complianceEvents: Events<ComplianceEvents> = defineEvents({
  "control.created": event<ControlSavedEventData>(),
  "control.updated": event<ControlSavedEventData>(),
  "control.evidence_added": event<ControlEvidenceAddedEventData>(),
  "evidence_task.missed": event<EvidenceTaskMissedEventData>(),
  "compliance_policy.published": event<PolicyPublishedEventData>(),
});
