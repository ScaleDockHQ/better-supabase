import type { DriveEvents } from "../../blocks/drive/events.ts";
import type { BlockSqlEvents, BlockSqlNames } from "../context.ts";

export const PATH_SEGMENT = "drive-nodes";

const SUBJECT = ["organizationId", "subjectType", "subjectId"] as const;

const EVENTS: BlockSqlEvents<DriveEvents> = {
  "drive.node_created": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "kind", "name", "parentId"],
  },
  "drive.node_renamed": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "name", "previousName"],
  },
  "drive.node_moved": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "parentId", "previousParentId"],
  },
  "drive.node_shared": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "principalType", "principalId", "role"],
  },
  "drive.node_unshared": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "principalType", "principalId"],
  },
  "drive.node_hold_placed": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "legalHoldUntil"],
  },
  "drive.node_hold_released": { subject: PATH_SEGMENT, payload: [...SUBJECT] },
  "drive.node_locked": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "lockedBy", "lockedUntil"],
  },
  "drive.node_unlocked": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "lockedBy", "forced"],
  },
  "drive.node_download_blocked_changed": {
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
  "drive.node_purged": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "objects"],
  },
};

export const NAMES: BlockSqlNames = {
  entities: { node: { table: "nodes", singular: "drive_node", primary: true } },
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
    "subjectType",
    "conflict",
    "drives",
    "driveKinds",
    "sources",
    "roleFunctions",
    "readPolicy",
    "previewPrefix",
    "extraColumns",
  ],
  tables: {
    nodes: {
      name: "drive_nodes",
      app: {},
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
  },
};
