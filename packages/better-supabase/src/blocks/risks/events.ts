import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The `risk_matrix.*` events. */
export interface RiskMatrixEventData {
  readonly organizationId: string;
  /** The matrix. */
  readonly id: string;
  readonly key: string;
  readonly name: string;
  readonly isDefault: boolean;
}

/** What every `risk.*` event carries. */
export interface RiskEventData {
  readonly organizationId: string;
  /** The risk. */
  readonly id: string;
  /** Its number, such as `RSK-0001`. */
  readonly number: string;
  readonly title: string;
  /** Its status after the change. */
  readonly status: string;
}

/** `risk.assessed`: the scores and bands of the new assessment. */
export interface RiskAssessedEventData extends RiskEventData {
  readonly assessmentId: string;
  readonly inherentScore: number;
  readonly inherentBand: string;
  readonly residualScore: number;
  readonly residualBand: string;
}

/** `risk.treatment_changed`. */
export interface RiskTreatmentChangedEventData extends RiskEventData {
  /** `mitigate`, `accept`, `transfer` or `avoid`. */
  readonly treatment: string;
  readonly note: string | null;
}

/** `risk.reviewed`. */
export interface RiskReviewedEventData extends RiskEventData {
  /** The next review date, `YYYY-MM-DD`. */
  readonly nextReviewOn: string;
  readonly note: string | null;
}

/** `risk.closed`. */
export interface RiskClosedEventData extends RiskEventData {
  readonly reason: string;
}

/** `risk.review_date_reached`: the review date has come. */
export interface RiskReviewDateReachedEventData extends RiskEventData {
  readonly ownerId: string | null;
  /** The review date that came, `YYYY-MM-DD`. */
  readonly nextReviewOn: string;
}

/** The events of the `risks` block: type to data. */
export type RisksEvents = {
  readonly "risk_matrix.created": RiskMatrixEventData;
  readonly "risk_matrix.updated": RiskMatrixEventData;
  readonly "risk.created": RiskEventData;
  readonly "risk.updated": RiskEventData;
  readonly "risk.assessed": RiskAssessedEventData;
  readonly "risk.treatment_changed": RiskTreatmentChangedEventData;
  readonly "risk.reviewed": RiskReviewedEventData;
  readonly "risk.closed": RiskClosedEventData;
  readonly "risk.review_date_reached": RiskReviewDateReachedEventData;
};

/** The `risks` block's event types, for its manifest and `onBlockEvent`. */
export const risksEvents: Events<RisksEvents> = defineEvents({
  "risk_matrix.created": event<RiskMatrixEventData>(),
  "risk_matrix.updated": event<RiskMatrixEventData>(),
  "risk.created": event<RiskEventData>(),
  "risk.updated": event<RiskEventData>(),
  "risk.assessed": event<RiskAssessedEventData>(),
  "risk.treatment_changed": event<RiskTreatmentChangedEventData>(),
  "risk.reviewed": event<RiskReviewedEventData>(),
  "risk.closed": event<RiskClosedEventData>(),
  "risk.review_date_reached": event<RiskReviewDateReachedEventData>(),
});
