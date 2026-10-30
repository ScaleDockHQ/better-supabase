import type { SsoEvents } from "../../blocks/sso/events.ts";
import type { BlockSqlEvents, BlockSqlNames } from "../context.ts";

const EVENTS: BlockSqlEvents<SsoEvents> = {
  "organization.member_removed": {
    subject: "organizations",
    payload: ["organizationId", "userId"],
  },
  "organization.member_added": {
    subject: "organizations",
    payload: ["organizationId", "userId", "role"],
  },
  "organization.role_changed": {
    subject: "organizations",
    payload: ["organizationId", "userId", "role", "previousRole"],
  },
  "sso_domain.created": {
    subject: "organizations",
    payload: ["organizationId", "domainId", "domain", "userId"],
  },
  "sso_domain.updated": {
    subject: "organizations",
    payload: ["organizationId", "domainId", "domain", "userId"],
  },
  "sso_domain.deleted": {
    subject: "organizations",
    payload: ["organizationId", "domainId", "domain", "userId"],
  },
  "sso_domain.verified": {
    subject: "organizations",
    payload: ["organizationId", "domainId", "domain", "userId"],
  },
  "sso_provider.registered": {
    subject: "organizations",
    payload: ["organizationId", "providerId", "domains", "userId"],
  },
  "sso_provider.unregistered": {
    subject: "organizations",
    payload: ["organizationId", "providerId", "domains", "userId"],
  },
  "scim_user.created": {
    subject: "organizations",
    payload: ["organizationId", "scimUserId"],
  },
  "scim_user.updated": {
    subject: "organizations",
    payload: ["organizationId", "scimUserId"],
  },
  "scim_user.deleted": {
    subject: "organizations",
    payload: ["organizationId", "scimUserId"],
  },
  "scim_group.created": {
    subject: "organizations",
    payload: ["organizationId", "scimGroupId"],
  },
  "scim_group.updated": {
    subject: "organizations",
    payload: ["organizationId", "scimGroupId"],
  },
  "scim_group.deleted": {
    subject: "organizations",
    payload: ["organizationId", "scimGroupId"],
  },
};

/** The sso module's events and tables. */
export const NAMES: BlockSqlNames = {
  events: EVENTS,
  options: ["txtPrefix", "defaultRole", "roleOrder", "groupRoles", "syncLog"],
  hooks: [],
  tables: {
    domains: {
      name: "organization_domains",
      lifecycle: { tenant: "tenant" },
      app: {},
      optional: ["createdBy", "createdAt"],
      typed: ["autoJoinRole"],
      columns: {
        id: "id",
        tenant: "organization_id",
        domain: "domain",
        token: "verification_token",
        verifiedAt: "verified_at",
        autoJoinRole: "auto_join_role",
        enforceSso: "enforce_sso",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
    providers: {
      name: "organization_sso_providers",
      lifecycle: { tenant: "tenant" },
      app: {},
      optional: ["metadataUrl"],
      typed: ["type"],
      columns: {
        id: "id",
        tenant: "organization_id",
        type: "type",
        metadataUrl: "metadata_url",
        domains: "domains",
        createdAt: "created_at",
      },
    },
    scimUsers: {
      name: "scim_users",
      lifecycle: { user: "user", tenant: "tenant" },
      app: {},
      optional: ["displayName", "givenName", "familyName", "updatedAt"],
      columns: {
        id: "id",
        tenant: "organization_id",
        user: "user_id",
        externalId: "external_id",
        userName: "user_name",
        displayName: "display_name",
        givenName: "given_name",
        familyName: "family_name",
        email: "email",
        emails: "emails",
        active: "active",
        version: "version",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    scimGroups: {
      name: "scim_groups",
      lifecycle: { tenant: "tenant" },
      app: {},
      optional: ["updatedAt"],
      typed: ["role"],
      columns: {
        id: "id",
        tenant: "organization_id",
        displayName: "display_name",
        externalId: "external_id",
        role: "role",
        version: "version",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    scimMembers: {
      name: "scim_group_members",
      app: {},
      columns: { group: "group_id", member: "scim_user_id" },
    },
    syncLog: {
      name: "scim_sync_log",
      app: {},
      optional: ["error", "requestId"],
      typed: ["operation", "resourceType"],
      columns: {
        id: "id",
        tenant: "organization_id",
        operation: "operation",
        resourceType: "resource_type",
        resourceId: "resource_id",
        status: "status",
        error: "error",
        requestId: "request_id",
        createdAt: "created_at",
      },
    },
  },
};
