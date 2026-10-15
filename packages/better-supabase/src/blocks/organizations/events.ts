import type {
  InvitationEventData,
  OrganizationEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `organizations` block: type to data. */
export type OrganizationsEvents = {
  readonly "organization.created": OrganizationEventData;
  readonly "organization.updated": OrganizationEventData;
  readonly "organization.deleted": OrganizationEventData;
  readonly "organization.member_added": OrganizationEventData;
  readonly "organization.member_removed": OrganizationEventData;
  readonly "organization.member_left": OrganizationEventData;
  readonly "organization.member_suspended": OrganizationEventData;
  readonly "organization.member_resumed": OrganizationEventData;
  readonly "organization.role_changed": OrganizationEventData;
  readonly "organization.ownership_transferred": OrganizationEventData;
  readonly "organization.switched": OrganizationEventData;
  readonly "invitation.created": InvitationEventData;
  readonly "invitation.resent": InvitationEventData;
  readonly "invitation.updated": InvitationEventData;
  readonly "invitation.accepted": InvitationEventData;
  readonly "invitation.declined": InvitationEventData;
  readonly "invitation.revoked": InvitationEventData;
};

/** The `organizations` block's event types, for its manifest and `onBlockEvent`. */
export const organizationsEvents: Events<OrganizationsEvents> = defineEvents({
  "organization.created": event<OrganizationEventData>(),
  "organization.updated": event<OrganizationEventData>(),
  "organization.deleted": event<OrganizationEventData>(),
  "organization.member_added": event<OrganizationEventData>(),
  "organization.member_removed": event<OrganizationEventData>(),
  "organization.member_left": event<OrganizationEventData>(),
  "organization.member_suspended": event<OrganizationEventData>(),
  "organization.member_resumed": event<OrganizationEventData>(),
  "organization.role_changed": event<OrganizationEventData>(),
  "organization.ownership_transferred": event<OrganizationEventData>(),
  "organization.switched": event<OrganizationEventData>(),
  "invitation.created": event<InvitationEventData>(),
  "invitation.resent": event<InvitationEventData>(),
  "invitation.updated": event<InvitationEventData>(),
  "invitation.accepted": event<InvitationEventData>(),
  "invitation.declined": event<InvitationEventData>(),
  "invitation.revoked": event<InvitationEventData>(),
});
