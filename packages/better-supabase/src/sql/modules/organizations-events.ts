import type { ModuleEvents } from "../context.ts";

/** The outbox events the module records. */
export const ORGANIZATION_EVENTS: ModuleEvents = {
  "organization.created": {
    subject: "organizations",
    payload: ["organizationId", "userId", "role"],
  },
  "organization.updated": {
    subject: "organizations",
    payload: ["organizationId", "userId"],
  },
  "organization.deleted": {
    subject: "organizations",
    payload: ["organizationId", "userId"],
  },
  "organization.role_changed": {
    subject: "organizations",
    payload: ["organizationId", "userId", "role", "previousRole"],
  },
  "organization.member_removed": {
    subject: "organizations",
    payload: ["organizationId", "userId"],
  },
  "organization.member_left": {
    subject: "organizations",
    payload: ["organizationId", "userId"],
  },
  "organization.ownership_transferred": {
    subject: "organizations",
    payload: ["organizationId", "userId", "role"],
  },
  "organization.member_suspended": {
    subject: "organizations",
    payload: ["organizationId", "userId"],
  },
  "organization.member_resumed": {
    subject: "organizations",
    payload: ["organizationId", "userId"],
  },
  "organization.switched": {
    subject: "organizations",
    payload: ["organizationId", "userId"],
  },
};
