import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What every `care_alert.*` event carries. */
export interface CareAlertEventData {
  readonly organizationId: string;
  readonly id: string;
  /** The record the alert is about, any registered subject. */
  readonly subjectType: string;
  readonly subjectId: string;
  /** `dose_range`, `duplicate_therapy`, `interaction`, `allergy` or `other`. */
  readonly kind: string;
  /** `info`, `warning` or `critical`. */
  readonly severity: string;
  /** `built-in` or the key of the external engine. */
  readonly source: string;
  /** `open`, `acknowledged`, `overridden` or `resolved`. */
  readonly status: string;
}

/** What every `care_rule.*` event carries. */
export interface CareRuleEventData {
  readonly organizationId: string;
  readonly id: string;
  /** `dose_range`, `duplicate_therapy` or `interaction`. */
  readonly kind: string;
  readonly severity: string;
}

/** The events of the `clinical-decision-support` block: type to data. */
export type ClinicalDecisionSupportEvents = {
  readonly "care_alert.raised": CareAlertEventData;
  readonly "care_alert.decided": CareAlertEventData;
  readonly "care_alert.resolved": CareAlertEventData;
  readonly "care_rule.created": CareRuleEventData;
  readonly "care_rule.updated": CareRuleEventData;
  readonly "care_rule.deleted": CareRuleEventData;
};

/**
 * The `clinical-decision-support` block's event types, for its manifest and
 * `onBlockEvent`.
 */
export const clinicalDecisionSupportEvents: Events<ClinicalDecisionSupportEvents> =
  defineEvents({
    "care_alert.raised": event<CareAlertEventData>(),
    "care_alert.decided": event<CareAlertEventData>(),
    "care_alert.resolved": event<CareAlertEventData>(),
    "care_rule.created": event<CareRuleEventData>(),
    "care_rule.updated": event<CareRuleEventData>(),
    "care_rule.deleted": event<CareRuleEventData>(),
  });
