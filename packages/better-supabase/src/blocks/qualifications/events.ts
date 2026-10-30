import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `qualification_type.created` and `.updated`: a type was saved. */
export interface QualificationTypeSavedEventData {
  readonly organizationId: string;
  readonly qualificationTypeId: string;
  readonly key: string;
  readonly name: string;
}

/** `qualification_type.archived`: a type no longer takes new holdings. */
export interface QualificationTypeArchivedEventData {
  readonly organizationId: string;
  readonly qualificationTypeId: string;
  readonly key: string;
}

/** `qualification.granted`: a holder received a qualification. */
export interface QualificationGrantedEventData {
  readonly organizationId: string;
  readonly qualificationId: string;
  readonly qualificationTypeId: string;
  readonly typeKey: string;
  readonly holderType: string;
  readonly holderId: string;
  /** `YYYY-MM-DD`. */
  readonly grantedOn: string;
  /** `YYYY-MM-DD`, or null when the qualification never expires. */
  readonly expiresOn: string | null;
  /** `manual`, `course` or `import`. */
  readonly source: string;
}

/** `qualification.revoked`: a holding was withdrawn. */
export interface QualificationRevokedEventData {
  readonly organizationId: string;
  readonly qualificationId: string;
  readonly qualificationTypeId: string;
  readonly typeKey: string;
  readonly holderType: string;
  readonly holderId: string;
  readonly reason: string | null;
}

/**
 * `qualification.expiry_warned` and `.expired`: a holding entered the renewal
 * window or passed its expiry date without a newer one.
 */
export interface QualificationExpiryEventData {
  readonly organizationId: string;
  readonly qualificationId: string;
  readonly qualificationTypeId: string;
  readonly typeKey: string;
  readonly holderType: string;
  readonly holderId: string;
  /** `YYYY-MM-DD`. */
  readonly expiresOn: string;
}

/** The events of the `qualifications` block: type to data. */
export type QualificationsEvents = {
  readonly "qualification_type.created": QualificationTypeSavedEventData;
  readonly "qualification_type.updated": QualificationTypeSavedEventData;
  readonly "qualification_type.archived": QualificationTypeArchivedEventData;
  readonly "qualification.granted": QualificationGrantedEventData;
  readonly "qualification.revoked": QualificationRevokedEventData;
  readonly "qualification.expiry_warned": QualificationExpiryEventData;
  readonly "qualification.expired": QualificationExpiryEventData;
};

/**
 * The `qualifications` block's event types, for its manifest and
 * `onBlockEvent`.
 */
export const qualificationsEvents: Events<QualificationsEvents> = defineEvents({
  "qualification_type.created": event<QualificationTypeSavedEventData>(),
  "qualification_type.updated": event<QualificationTypeSavedEventData>(),
  "qualification_type.archived": event<QualificationTypeArchivedEventData>(),
  "qualification.granted": event<QualificationGrantedEventData>(),
  "qualification.revoked": event<QualificationRevokedEventData>(),
  "qualification.expiry_warned": event<QualificationExpiryEventData>(),
  "qualification.expired": event<QualificationExpiryEventData>(),
});
