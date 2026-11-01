import type { DriveEvents } from "../../blocks/drive/events.ts";
import type { BlockSqlEvents, BlockSqlNames } from "../context.ts";

export const PATH_SEGMENT = "drive-nodes";

const SUBJECT = ["organizationId", "subjectType", "subjectId"] as const;

/** The node columns `options.control` adds for controlled documents. */
export const DOCUMENT_COLUMNS = [
  "documentNumber",
  "documentType",
  "documentStatus",
  "documentOwner",
  "effectiveVersion",
  "effectiveFrom",
  "reviewIntervalMonths",
  "nextReviewOn",
  "reviewNotifiedFor",
] as const;

const EVENTS: BlockSqlEvents<DriveEvents> = {
  "drive_node.created": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "kind", "name", "parentId", "source"],
  },
  "drive_node.renamed": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "name", "previousName"],
  },
  "drive_node.moved": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "parentId", "previousParentId"],
  },
  "drive_node.shared": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "principalType", "principalId", "role"],
  },
  "drive_node.unshared": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "principalType", "principalId"],
  },
  "drive_node.hold_placed": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "legalHoldUntil"],
  },
  "drive_node.hold_released": { subject: PATH_SEGMENT, payload: [...SUBJECT] },
  "drive_node.locked": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "lockedBy", "lockedUntil"],
  },
  "drive_node.unlocked": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "lockedBy", "forced"],
  },
  "drive_node.download_blocked_changed": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "downloadBlocked"],
  },
  "drive.download_blocked_changed": {
    subject: "drives",
    payload: [...SUBJECT, "downloadBlocked"],
  },
  "drive.created": { subject: "drives", payload: [...SUBJECT, "name"] },
  "drive.renamed": {
    subject: "drives",
    payload: [...SUBJECT, "name", "previousName"],
  },
  "drive.deleted": { subject: "drives", payload: [...SUBJECT] },
  "drive.shared": {
    subject: "drives",
    payload: [...SUBJECT, "principalType", "principalId", "role"],
  },
  "drive.unshared": {
    subject: "drives",
    payload: [...SUBJECT, "principalType", "principalId"],
  },
  "drive_node.ownership_transferred": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "fromUserId", "toUserId"],
  },
  "drive.ownership_transferred": {
    subject: "drives",
    payload: [...SUBJECT, "fromUserId", "toUserId"],
  },
  "drive.connection_created": {
    subject: "drive-connections",
    payload: [...SUBJECT, "name"],
  },
  "drive.connection_removed": {
    subject: "drive-connections",
    payload: [...SUBJECT],
  },
};

export const FILE_EVENTS: BlockSqlEvents<DriveEvents> = {
  "drive_node.purged": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "objects"],
  },
  "drive_node.document_saved": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "documentNumber", "documentType", "ownerId"],
  },
  "drive_node.submitted": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "documentNumber", "attachmentId", "requestId"],
  },
  "drive_node.released": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "documentNumber", "versionId", "attachmentId"],
  },
  "drive_node.obsoleted": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "documentNumber", "reason"],
  },
  "drive_node.reviewed": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "documentNumber", "outcome", "note", "nextReviewOn"],
  },
  "drive_node.review_requested": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "documentNumber", "ownerId", "nextReviewOn"],
  },
};

export const NAMES: BlockSqlNames = {
  entities: {
    drive_node: { table: "nodes", singular: "drive_node", primary: true },
  },
  events: EVENTS,
  hooks: [
    "before_drive_node_create",
    "after_drive_node_create",
    "before_drive_node_move",
    "after_drive_node_move",
    "before_drive_node_rename",
    "after_drive_node_rename",
    "before_drive_node_share",
    "after_drive_node_share",
  ],
  options: [
    "roles",
    "writeRole",
    "shareRole",
    "commentRole",
    "memberRole",
    "uploadRole",
    "subjectType",
    "conflict",
    "drives",
    "driveKinds",
    "sources",
    "roleFunctions",
    "readPolicy",
    "previewPrefix",
    "extraColumns",
    "maxTextBytes",
    "searchColumn",
    "quota",
    "control",
    "sync",
  ],
  tables: {
    nodes: {
      name: "drive_nodes",
      app: {
        unused: (ctx) =>
          ctx.option("control") === undefined ? DOCUMENT_COLUMNS : [],
      },
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        drive: "drive_id",
        parent: "parent_id",
        kind: "kind",
        name: "name",
        attachment: "attachment_id",
        path: "path",
        rank: "rank",
        deletedAt: "deleted_at",
        source: "source",
        externalId: "external_id",
        externalMetadata: "external_metadata",
        legalHoldUntil: "legal_hold_until",
        lockedBy: "locked_by",
        lockedUntil: "locked_until",
        lockNote: "lock_note",
        downloadBlocked: "download_blocked",
        previewPages: "preview_pages",
        documentNumber: "document_number",
        documentType: "document_type",
        documentStatus: "document_status",
        documentOwner: "document_owner_id",
        effectiveVersion: "effective_version_id",
        effectiveFrom: "effective_from",
        reviewIntervalMonths: "review_interval_months",
        nextReviewOn: "next_review_on",
        reviewNotifiedFor: "review_notified_for",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "drive",
        "attachment",
        "path",
        "rank",
        "deletedAt",
        "source",
        "externalId",
        "externalMetadata",
        "legalHoldUntil",
        "lockedBy",
        "lockedUntil",
        "lockNote",
        "downloadBlocked",
        "previewPages",
        "documentNumber",
        "documentType",
        "documentStatus",
        "documentOwner",
        "effectiveVersion",
        "effectiveFrom",
        "reviewIntervalMonths",
        "nextReviewOn",
        "reviewNotifiedFor",
        "createdBy",
        "updatedAt",
      ],
      typed: ["kind", "source"],
    },
    grants: {
      name: "drive_grants",
      app: {
        unused: (ctx) =>
          ctx.has("grants", "principalType")
            ? ["user", "team"]
            : ["principalType", "principalId"],
      },
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        node: "node_id",
        principalType: "principal_type",
        principalId: "principal_id",
        user: "user_id",
        team: "team_id",
        role: "role",
        expiresAt: "expires_at",
        accessRequest: "access_request",
        createdBy: "created_by",
        createdAt: "created_at",
      },
      optional: [
        "principalType",
        "principalId",
        "user",
        "team",
        "expiresAt",
        "accessRequest",
        "createdBy",
      ],
      typed: ["role"],
    },
    drives: {
      name: "drive_drives",
      app: {},
      optionalTable: true,
      lifecycle: { tenant: "tenant", user: "owner", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        kind: "kind",
        owner: "owner_id",
        connection: "connection_id",
        downloadBlocked: "download_blocked",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "kind",
        "owner",
        "connection",
        "downloadBlocked",
        "createdBy",
        "updatedAt",
      ],
      typed: ["kind"],
    },
    driveGrants: {
      name: "drive_drive_grants",
      app: {
        unused: (ctx) =>
          ctx.has("driveGrants", "principalType")
            ? ["user", "team"]
            : ["principalType", "principalId"],
      },
      optionalTable: true,
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        drive: "drive_id",
        principalType: "principal_type",
        principalId: "principal_id",
        user: "user_id",
        team: "team_id",
        role: "role",
        expiresAt: "expires_at",
        createdBy: "created_by",
        createdAt: "created_at",
      },
      optional: [
        "principalType",
        "principalId",
        "user",
        "team",
        "expiresAt",
        "createdBy",
      ],
      typed: ["role"],
    },
    connections: {
      name: "drive_connections",
      app: {},
      optionalTable: true,
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        user: "user_id",
        provider: "provider",
        name: "name",
        status: "status",
        syncCursor: "sync_cursor",
        syncClaimedAt: "sync_claimed_at",
        lastSyncedAt: "last_synced_at",
        lastSyncError: "last_sync_error",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "syncCursor",
        "syncClaimedAt",
        "lastSyncedAt",
        "lastSyncError",
        "createdBy",
        "updatedAt",
      ],
      typed: ["provider", "status"],
    },
    texts: {
      name: "drive_node_texts",
      app: {},
      optionalTable: true,
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        node: "node_id",
        tenant: "tenant_id",
        attachment: "attachment_id",
        extractor: "extractor",
        content: "content",
        extractedAt: "extracted_at",
      },
      optional: ["extractor", "extractedAt"],
    },
  },
};
