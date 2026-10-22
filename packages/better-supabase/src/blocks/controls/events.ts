import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `control.saved`: a control was created or changed. */
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

/** `policy.published`: a policy has a new current version. */
export interface PolicyPublishedEventData {
  readonly organizationId: string;
  readonly policyId: string;
  readonly versionId: string;
  readonly number: number;
}

/** `policy.acknowledged`: a member acknowledged a policy's current version. */
export interface PolicyAcknowledgedEventData {
  readonly organizationId: string;
  readonly policyId: string;
  readonly versionId: string;
  readonly userId: string;
}

/** The events of the `controls` block: type to data. */
export type ControlsEvents = {
  readonly "control.saved": ControlSavedEventData;
  readonly "control.evidence_added": ControlEvidenceAddedEventData;
  readonly "evidence_task.missed": EvidenceTaskMissedEventData;
  readonly "policy.published": PolicyPublishedEventData;
  readonly "policy.acknowledged": PolicyAcknowledgedEventData;
};

/** The `controls` block's event types, for its manifest and `onBlockEvent`. */
export const controlsEvents: Events<ControlsEvents> = defineEvents({
  "control.saved": event<ControlSavedEventData>(),
  "control.evidence_added": event<ControlEvidenceAddedEventData>(),
  "evidence_task.missed": event<EvidenceTaskMissedEventData>(),
  "policy.published": event<PolicyPublishedEventData>(),
  "policy.acknowledged": event<PolicyAcknowledgedEventData>(),
});
