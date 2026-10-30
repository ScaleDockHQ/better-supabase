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
  readonly "sso_domain.created": OrganizationDomainEventData;
  readonly "sso_domain.updated": OrganizationDomainEventData;
  readonly "sso_domain.verified": OrganizationDomainEventData;
  readonly "sso_domain.deleted": OrganizationDomainEventData;
  readonly "sso_provider.registered": SsoProviderEventData;
  readonly "sso_provider.unregistered": SsoProviderEventData;
  readonly "scim_user.created": ScimEventData;
  readonly "scim_user.updated": ScimEventData;
  readonly "scim_user.deleted": ScimEventData;
  readonly "scim_group.created": ScimEventData;
  readonly "scim_group.updated": ScimEventData;
  readonly "scim_group.deleted": ScimEventData;
};

/** The `sso` block's event types, for its manifest and `onBlockEvent`. */
export const ssoEvents: Events<SsoEvents> = defineEvents({
  "organization.member_added": event<OrganizationEventData>(),
  "organization.member_removed": event<OrganizationEventData>(),
  "organization.role_changed": event<OrganizationEventData>(),
  "sso_domain.created": event<OrganizationDomainEventData>(),
  "sso_domain.updated": event<OrganizationDomainEventData>(),
  "sso_domain.verified": event<OrganizationDomainEventData>(),
  "sso_domain.deleted": event<OrganizationDomainEventData>(),
  "sso_provider.registered": event<SsoProviderEventData>(),
  "sso_provider.unregistered": event<SsoProviderEventData>(),
  "scim_user.created": event<ScimEventData>(),
  "scim_user.updated": event<ScimEventData>(),
  "scim_user.deleted": event<ScimEventData>(),
  "scim_group.created": event<ScimEventData>(),
  "scim_group.updated": event<ScimEventData>(),
  "scim_group.deleted": event<ScimEventData>(),
});
