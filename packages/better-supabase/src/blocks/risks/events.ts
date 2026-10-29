import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** A risk matrix was saved. */
export interface RiskMatrixSavedEventData {
  readonly organizationId: string;
  readonly matrixId: string;
  readonly key: string;
}

/** A risk was created or changed. */
export interface RiskCreatedEventData {
  readonly organizationId: string;
  readonly riskId: string;
  readonly number: string;
  readonly nextReviewOn?: string;
}

/** A risk changed. */
export interface RiskUpdatedEventData extends RiskCreatedEventData {
  readonly changed: readonly string[];
}

/** A risk was assessed. */
export interface RiskAssessedEventData extends RiskCreatedEventData {
  readonly inherentBand: string;
  readonly residualBand: string;
}

/** A risk's treatment changed. */
export interface RiskTreatmentChangedEventData extends RiskCreatedEventData {
  readonly treatment: string;
}

/** A risk was reviewed, closed or is due. */
export type RiskLifecycleEventData = RiskCreatedEventData;

/** The events of the `risks` block. */
export type RisksEvents = {
  readonly "risk_matrix.created": RiskMatrixSavedEventData;
  readonly "risk_matrix.updated": RiskMatrixSavedEventData;
  readonly "risk.created": RiskCreatedEventData;
  readonly "risk.updated": RiskUpdatedEventData;
  readonly "risk.assessed": RiskAssessedEventData;
  readonly "risk.treatment_changed": RiskTreatmentChangedEventData;
  readonly "risk.reviewed": RiskLifecycleEventData;
  readonly "risk.closed": RiskLifecycleEventData;
  readonly "risk.review_reminded": RiskLifecycleEventData;
};

export const risksEvents: Events<RisksEvents> = defineEvents({
  "risk_matrix.created": event<RiskMatrixSavedEventData>(),
  "risk_matrix.updated": event<RiskMatrixSavedEventData>(),
  "risk.created": event<RiskCreatedEventData>(),
  "risk.updated": event<RiskUpdatedEventData>(),
  "risk.assessed": event<RiskAssessedEventData>(),
  "risk.treatment_changed": event<RiskTreatmentChangedEventData>(),
  "risk.reviewed": event<RiskLifecycleEventData>(),
  "risk.closed": event<RiskLifecycleEventData>(),
  "risk.review_reminded": event<RiskLifecycleEventData>(),
});
