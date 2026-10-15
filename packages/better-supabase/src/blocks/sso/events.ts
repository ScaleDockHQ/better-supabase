import type {
  OrganizationDomainEventData,
  OrganizationEventData,
  ScimEventData,
  SsoProviderEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `sso` block: type to data. */
export type SsoEvents = {
  readonly "organization.member_added": OrganizationEventData;
  readonly "organization.member_removed": OrganizationEventData;
  readonly "organization.role_changed": OrganizationEventData;
  readonly "organization.domain_added": OrganizationDomainEventData;
  readonly "organization.domain_updated": OrganizationDomainEventData;
  readonly "organization.domain_verified": OrganizationDomainEventData;
  readonly "organization.domain_removed": OrganizationDomainEventData;
  readonly "sso_provider.registered": SsoProviderEventData;
  readonly "sso_provider.unregistered": SsoProviderEventData;
  readonly "scim_user.saved": ScimEventData;
  readonly "scim_user.deleted": ScimEventData;
  readonly "scim_group.saved": ScimEventData;
  readonly "scim_group.deleted": ScimEventData;
};

/** The `sso` block's event types, for its manifest and `onBlockEvent`. */
export const ssoEvents: Events<SsoEvents> = defineEvents({
  "organization.member_added": event<OrganizationEventData>(),
  "organization.member_removed": event<OrganizationEventData>(),
  "organization.role_changed": event<OrganizationEventData>(),
  "organization.domain_added": event<OrganizationDomainEventData>(),
  "organization.domain_updated": event<OrganizationDomainEventData>(),
  "organization.domain_verified": event<OrganizationDomainEventData>(),
  "organization.domain_removed": event<OrganizationDomainEventData>(),
  "sso_provider.registered": event<SsoProviderEventData>(),
  "sso_provider.unregistered": event<SsoProviderEventData>(),
  "scim_user.saved": event<ScimEventData>(),
  "scim_user.deleted": event<ScimEventData>(),
  "scim_group.saved": event<ScimEventData>(),
  "scim_group.deleted": event<ScimEventData>(),
});
