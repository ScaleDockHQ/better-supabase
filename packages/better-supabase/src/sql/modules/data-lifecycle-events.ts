import type { ModuleEvents } from "../context.ts";

/** The outbox events the module records. */
export const DATA_LIFECYCLE_EVENTS: ModuleEvents = {
  "data_export.requested": {
    subject: "data-exports",
    payload: ["exportId", "subject", "organizationId", "userId", "requestedBy"],
  },
  "data_export.completed": {
    subject: "data-exports",
    payload: [
      "exportId",
      "subject",
      "organizationId",
      "userId",
      "requestedBy",
      "files",
      "expiresAt",
    ],
    retries: true,
  },
  "data_export.failed": {
    subject: "data-exports",
    payload: [
      "exportId",
      "subject",
      "organizationId",
      "userId",
      "requestedBy",
      "error",
    ],
    retries: true,
  },
  "organization.deletion_requested": {
    subject: "organizations",
    payload: ["organizationId", "userId", "purgeAfter"],
  },
  "organization.deletion_cancelled": {
    subject: "organizations",
    payload: ["organizationId", "userId", "purgeAfter"],
  },
  "organization.purged": {
    subject: "organizations",
    payload: ["organizationId", "userId", "purgeAfter"],
    retries: true,
  },
};
