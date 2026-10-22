import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `guest.invited`. */
export interface GuestInvitedEventData {
  readonly organizationId: string;
  /** The guest. */
  readonly id: string;
  readonly email: string;
  /** The party the guest acts for, such as a customer company, when set. */
  readonly partyType: string | null;
  readonly partyId: string | null;
}

/** `guest.accepted`. */
export interface GuestAcceptedEventData {
  readonly organizationId: string;
  readonly id: string;
  /** The user who accepted the invite. */
  readonly userId: string;
}

/** `guest.revoked`. */
export interface GuestRevokedEventData {
  readonly organizationId: string;
  readonly id: string;
}

/** `guest_grant.created` and `guest_grant.revoked`. */
export interface GuestGrantEventData {
  readonly organizationId: string;
  /** The grant. */
  readonly id: string;
  readonly guestId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** `read`, `comment` and `upload`, in that order. */
  readonly actions: readonly string[];
}

/** The events of the `guests` block: type to data. */
export type GuestsEvents = {
  readonly "guest.invited": GuestInvitedEventData;
  readonly "guest.accepted": GuestAcceptedEventData;
  readonly "guest.revoked": GuestRevokedEventData;
  readonly "guest_grant.created": GuestGrantEventData;
  readonly "guest_grant.revoked": GuestGrantEventData;
};

/** The `guests` block's event types, for its manifest and `onBlockEvent`. */
export const guestsEvents: Events<GuestsEvents> = defineEvents({
  "guest.invited": event<GuestInvitedEventData>(),
  "guest.accepted": event<GuestAcceptedEventData>(),
  "guest.revoked": event<GuestRevokedEventData>(),
  "guest_grant.created": event<GuestGrantEventData>(),
  "guest_grant.revoked": event<GuestGrantEventData>(),
});
