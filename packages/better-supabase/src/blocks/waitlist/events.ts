import type {
  Events,
  InviteCodeEventData,
  OrganizationEventData,
  WaitlistEventData,
} from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `waitlist` block: type to data. */
export type WaitlistEvents = {
  readonly "organization.member_added": OrganizationEventData;
  readonly "waitlist.approved": WaitlistEventData;
  readonly "waitlist.rejected": WaitlistEventData;
  readonly "invite_code.created": InviteCodeEventData;
  readonly "invite_code.revoked": InviteCodeEventData;
};

/** The `waitlist` block's event types, for its manifest and `onBlockEvent`. */
export const waitlistEvents: Events<WaitlistEvents> = defineEvents({
  "organization.member_added": event<OrganizationEventData>(),
  "waitlist.approved": event<WaitlistEventData>(),
  "waitlist.rejected": event<WaitlistEventData>(),
  "invite_code.created": event<InviteCodeEventData>(),
  "invite_code.revoked": event<InviteCodeEventData>(),
});
