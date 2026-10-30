import type {
  InviteCodeEventData,
  OrganizationEventData,
  WaitlistEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `waitlist` block: type to data. */
export type WaitlistEvents = {
  readonly "organization.member_added": OrganizationEventData;
  readonly "waitlist_entry.approved": WaitlistEventData;
  readonly "waitlist_entry.rejected": WaitlistEventData;
  readonly "invite_code.created": InviteCodeEventData;
  readonly "invite_code.revoked": InviteCodeEventData;
};

/** The `waitlist` block's event types, for its manifest and `onBlockEvent`. */
export const waitlistEvents: Events<WaitlistEvents> = defineEvents({
  "organization.member_added": event<OrganizationEventData>(),
  "waitlist_entry.approved": event<WaitlistEventData>(),
  "waitlist_entry.rejected": event<WaitlistEventData>(),
  "invite_code.created": event<InviteCodeEventData>(),
  "invite_code.revoked": event<InviteCodeEventData>(),
});
