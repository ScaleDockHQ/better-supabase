import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The `consent.*` events. */
export interface ConsentEventData {
  readonly organizationId: string;
  readonly consentId: string;
  readonly purposeId: string;
  readonly purposeKey: string;
  /** The record the consent is about. */
  readonly subjectType: string;
  readonly subjectId: string;
  /** Granted, refused, withdrawn or expired, after the change. */
  readonly status: string;
  /** `self` or `representative`. */
  readonly givenBy: string;
}

/** The `consent_purpose.*` events. */
export interface ConsentPurposeEventData {
  /** Null for a system purpose. */
  readonly organizationId: string | null;
  readonly purposeId: string;
  readonly key: string;
  readonly version: string;
}

/** The events of the `consents` block: type to data. */
export type ConsentsEvents = {
  readonly "consent.granted": ConsentEventData;
  readonly "consent.refused": ConsentEventData;
  readonly "consent.withdrawn": ConsentEventData;
  readonly "consent.expired": ConsentEventData;
  readonly "consent_purpose.created": ConsentPurposeEventData;
  readonly "consent_purpose.updated": ConsentPurposeEventData;
};

/** The `consents` block's event types, for its manifest and `onBlockEvent`. */
export const consentsEvents: Events<ConsentsEvents> = defineEvents({
  "consent.granted": event<ConsentEventData>(),
  "consent.refused": event<ConsentEventData>(),
  "consent.withdrawn": event<ConsentEventData>(),
  "consent.expired": event<ConsentEventData>(),
  "consent_purpose.created": event<ConsentPurposeEventData>(),
  "consent_purpose.updated": event<ConsentPurposeEventData>(),
});
