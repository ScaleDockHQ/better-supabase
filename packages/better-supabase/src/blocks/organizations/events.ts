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
  readonly "organization.role_added": OrganizationEventData;
  readonly "organization.role_removed": OrganizationEventData;
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
  "organization.created": event<OrganizationEventData>({ public: true }),
  "organization.updated": event<OrganizationEventData>({ public: true }),
  "organization.deleted": event<OrganizationEventData>({ public: true }),
  "organization.member_added": event<OrganizationEventData>({ public: true }),
  "organization.member_removed": event<OrganizationEventData>({ public: true }),
  "organization.member_left": event<OrganizationEventData>({ public: true }),
  "organization.member_suspended": event<OrganizationEventData>({
    public: true,
  }),
  "organization.member_resumed": event<OrganizationEventData>({ public: true }),
  "organization.role_changed": event<OrganizationEventData>({ public: true }),
  "organization.role_added": event<OrganizationEventData>({ public: true }),
  "organization.role_removed": event<OrganizationEventData>({ public: true }),
  "organization.ownership_transferred": event<OrganizationEventData>({
    public: true,
  }),
  "organization.switched": event<OrganizationEventData>(),
  "invitation.created": event<InvitationEventData>({ public: true }),
  "invitation.resent": event<InvitationEventData>({ public: true }),
  "invitation.updated": event<InvitationEventData>({ public: true }),
  "invitation.accepted": event<InvitationEventData>({ public: true }),
  "invitation.declined": event<InvitationEventData>({ public: true }),
  "invitation.revoked": event<InvitationEventData>({ public: true }),
});
