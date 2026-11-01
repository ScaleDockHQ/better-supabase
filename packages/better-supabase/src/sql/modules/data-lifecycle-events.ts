import type { DataLifecycleEvents } from "../../blocks/data-lifecycle/events.ts";
import type { BlockSqlEvents } from "../context.ts";

/** The outbox events the module records. */
export const DATA_LIFECYCLE_EVENTS: BlockSqlEvents<DataLifecycleEvents> = {
  "data_export.requested": {
    subject: "data-exports",
    payload: [
      "exportId",
      "subject",
      "organizationId",
      "userId",
      "requestedBy",
      "subjectType",
      "subjectId",
    ],
  },
  "data_export.completed": {
    subject: "data-exports",
    payload: [
      "exportId",
      "subject",
      "organizationId",
      "userId",
      "requestedBy",
      "subjectType",
      "subjectId",
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
      "subjectType",
      "subjectId",
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
  "legal_hold.placed": {
    subject: "legal-holds",
    payload: ["holdId", "organizationId", "kind", "reason"],
  },
  "legal_hold.released": {
    subject: "legal-holds",
    payload: ["holdId", "organizationId", "kind", "reason"],
  },
  "data_subject_request.received": {
    subject: "data-subject-requests",
    payload: ["requestId", "organizationId", "kind", "status", "dueAt"],
  },
  "data_subject_request.verified": {
    subject: "data-subject-requests",
    payload: ["requestId", "organizationId", "kind", "status", "dueAt"],
  },
  "data_subject_request.extended": {
    subject: "data-subject-requests",
    payload: ["requestId", "organizationId", "kind", "status", "dueAt"],
  },
  "data_subject_request.fulfilled": {
    subject: "data-subject-requests",
    payload: ["requestId", "organizationId", "kind", "status", "dueAt"],
  },
  "data_subject_request.refused": {
    subject: "data-subject-requests",
    payload: ["requestId", "organizationId", "kind", "status", "dueAt"],
  },
};
