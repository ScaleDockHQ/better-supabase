import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** A qualification type was saved. */
export interface QualificationTypeSavedEventData {
  readonly organizationId: string;
  readonly typeId: string;
  readonly key: string;
}

/** A qualification was granted. */
export interface QualificationGrantedEventData {
  readonly organizationId: string;
  readonly qualificationId: string;
  readonly typeKey: string;
  readonly holderType: string;
  readonly holderId: string;
}

/** A qualification was revoked. */
export interface QualificationRevokedEventData {
  readonly organizationId: string;
  readonly qualificationId: string;
}

/** A qualification is expiring. */
export interface QualificationExpiringEventData {
  readonly organizationId: string;
  readonly qualificationId: string;
  readonly holderType: string;
  readonly holderId: string;
  readonly expiresOn: string;
}

/** The events of the `qualifications` block. */
export type QualificationsEvents = {
  readonly "qualification_type.created": QualificationTypeSavedEventData;
  readonly "qualification_type.updated": QualificationTypeSavedEventData;
  readonly "qualification.granted": QualificationGrantedEventData;
  readonly "qualification.revoked": QualificationRevokedEventData;
  readonly "qualification.expired": QualificationExpiringEventData;
};

export const qualificationsEvents: Events<QualificationsEvents> =
  defineEvents({
    "qualification_type.created": event<QualificationTypeSavedEventData>(),
    "qualification_type.updated": event<QualificationTypeSavedEventData>(),
    "qualification.granted": event<QualificationGrantedEventData>(),
    "qualification.revoked": event<QualificationRevokedEventData>(),
    "qualification.expired": event<QualificationExpiringEventData>(),
  });
