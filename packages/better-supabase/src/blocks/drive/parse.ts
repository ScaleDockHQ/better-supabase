import type { BlockFields } from "../../core/block-fields.ts";
import type { Result } from "../../core/result.ts";
import type { ApprovalStatus } from "../approvals/approvals.ts";
import type { Attachment } from "../attachments/attachments.ts";
import type {
  Drive,
  DriveApproval,
  DriveApprovalState,
  DriveBatch,
  DriveBinEntry,
  DriveConnection,
  DriveDrive,
  DriveDriveGrant,
  DriveFile,
  DriveGrant,
  DriveLinkView,
  DriveNode,
  DriveNodeKind,
  DrivePreviews,
  DrivePrincipalType,
  DriveRevision,
  DriveStoredObject,
} from "./drive.ts";

import { AsyncResult, ok } from "../../core/result.ts";
import { attachmentOf } from "../attachments/attachments.ts";
import {
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export const KINDS: readonly DriveNodeKind[] = ["folder", "file"];

const APPROVAL_STATUSES: readonly ApprovalStatus[] = [
  "pending",
  "approved",
  "rejected",
  "cancelled",
  "expired",
];

const PRINCIPALS: readonly DrivePrincipalType[] = ["user", "team", "role"];

function fileOf(value: unknown): DriveFile | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  return {
    mimeType: textOf(value["mimeType"]),
    size: Number(value["size"]),
    status: textOf(value["status"]),
    uploadedAt: optionalInstant(value["uploadedAt"]),
  };
}

export function nodeOf(value: unknown, fn: string): DriveNode {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    parentId: optionalText(row["parentId"]) ?? null,
    kind: enumOrThrow(row["kind"], KINDS, "drive node kind"),
    name: textOf(row["name"]),
    rank: optionalText(row["rank"]),
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: optionalInstant(row["updatedAt"]),
    deletedAt: optionalInstant(row["deletedAt"]),
    attachmentId: optionalText(row["attachmentId"]),
    file: fileOf(row["file"]),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
    role: optionalText(row["role"]),
    driveId: optionalText(row["driveId"]),
    source: optionalText(row["source"]) ?? "internal",
    externalId: optionalText(row["externalId"]),
    externalMetadata: isRecord(row["externalMetadata"])
      ? row["externalMetadata"]
      : undefined,
    legalHoldUntil: optionalInstant(row["legalHoldUntil"]),
    readOnly: row["readOnly"] === true,
    held: row["held"] === true,
    lockedBy: optionalText(row["lockedBy"]),
    lockedUntil: optionalInstant(row["lockedUntil"]),
    lockNote: optionalText(row["lockNote"]),
    downloadBlocked: row["downloadBlocked"] === true,
    downloadable:
      typeof row["downloadable"] === "boolean"
        ? row["downloadable"]
        : undefined,
    previewPages: optionalCount(row["previewPages"]),
    starredAt: optionalInstant(row["starredAt"]),
    openedAt: optionalInstant(row["openedAt"]),
    labels: Array.isArray(row["labels"])
      ? recordsOf(row["labels"], fn).map((label) => ({
          id: textOf(label["id"]),
          name: textOf(label["name"]),
          color: optionalText(label["color"]),
        }))
      : undefined,
    approval: isRecord(row["approval"])
      ? approvalStateOf(row["approval"])
      : undefined,
  };
}

function approvalStateOf(
  row: Readonly<Record<string, unknown>>,
): DriveApprovalState {
  return {
    id: textOf(row["id"]),
    status: enumOrThrow(row["status"], APPROVAL_STATUSES, "approval status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    decidedAt: optionalInstant(row["decidedAt"]),
  };
}

export function approvalOf(value: unknown, fn: string): DriveApproval {
  const row = recordOf(value, fn);
  const revision = row["revision"];

  return {
    ...approvalStateOf(row),
    attachmentId: textOf(row["attachmentId"]),
    revision:
      revision === null || revision === undefined
        ? undefined
        : Number(revision),
    current: row["current"] === true,
    step: Number(row["step"]),
    reason: optionalText(row["reason"]),
    requestedBy: optionalText(row["requestedBy"]),
  };
}

export const nodesOf = (value: unknown, fn: string): DriveNode[] =>
  recordsOf(value, fn).map((row) => nodeOf(row, fn));

export function grantOf(value: unknown, fn: string): DriveGrant {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    nodeId: textOf(row["nodeId"]),
    principal: {
      type: enumOrThrow(row["principalType"], PRINCIPALS, "principal type"),
      id: textOf(row["principalId"]),
    },
    role: textOf(row["role"]),
    expiresAt: optionalInstant(row["expiresAt"]),
    inherited: row["inherited"] === true,
  };
}

export function driveOf(value: unknown, fn: string): DriveDrive {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    kind: textOf(row["kind"]),
    ownerId: optionalText(row["ownerId"]),
    connectionId: optionalText(row["connectionId"]),
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: optionalInstant(row["updatedAt"]),
    role: optionalText(row["role"]),
    readOnly: row["readOnly"] === true,
    downloadBlocked: row["downloadBlocked"] === true,
  };
}

export function driveGrantOf(value: unknown, fn: string): DriveDriveGrant {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    driveId: textOf(row["driveId"]),
    principal: {
      type: enumOrThrow(row["principalType"], PRINCIPALS, "principal type"),
      id: textOf(row["principalId"]),
    },
    role: textOf(row["role"]),
    expiresAt: optionalInstant(row["expiresAt"]),
  };
}

export function connectionOf(value: unknown, fn: string): DriveConnection {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    userId: optionalText(row["userId"]),
    provider: textOf(row["provider"]),
    name: textOf(row["name"]),
    status: textOf(row["status"]),
    syncCursor: optionalText(row["syncCursor"]),
    lastSyncedAt: optionalInstant(row["lastSyncedAt"]),
    lastSyncError: optionalText(row["lastSyncError"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: optionalInstant(row["updatedAt"]),
  };
}

export const drivesOf = (value: unknown, fn: string): DriveDrive[] =>
  recordsOf(value, fn).map((row) => driveOf(row, fn));

export const connectionsOf = (value: unknown, fn: string): DriveConnection[] =>
  recordsOf(value, fn).map((row) => connectionOf(row, fn));

export function batchOf(value: unknown, fn: string): DriveBatch {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    batchId: textOf(row["batchId"]),
    count: Number(row["count"]),
  };
}

export function revisionOf(value: unknown): DriveRevision {
  const row = recordOf(value, "drive_revisions");

  return {
    id: textOf(row["id"]),
    number: Number(row["number"]),
    label: optionalText(row["label"]),
    source: textOf(row["source"]),
    attachmentId: textOf(row["attachmentId"]),
    name: textOf(row["name"]),
    mimeType: textOf(row["mimeType"]),
    size: Number(row["size"]),
    current: row["current"] === true,
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  };
}

export function binEntryOf(value: unknown): DriveBinEntry {
  const row = recordOf(value, "drive_bin");

  return {
    ...batchOf(row, "drive_bin"),
    node: nodeOf(row["node"], "drive_bin"),
    trashedBy: optionalText(row["trashedBy"]),
    trashedAt: requiredInstant(row["trashedAt"], "trashedAt"),
    purgeAfter: optionalInstant(row["purgeAfter"]),
  };
}

export function linkOf(value: unknown): DriveLinkView {
  const row = recordOf(value, "drive_link");
  const link = recordOf(row["link"], "drive_link");
  const object = isRecord(row["object"]) ? row["object"] : undefined;

  return {
    link: {
      id: textOf(link["id"]),
      role: textOf(link["role"]),
      nodeId: textOf(link["nodeId"]),
      expiresAt: optionalInstant(link["expiresAt"]),
      downloadAllowed: link["downloadAllowed"] !== false,
    },
    node: nodeOf(row["node"], "drive_link"),
    children: Array.isArray(row["children"])
      ? nodesOf(row["children"], "drive_link")
      : undefined,
    object:
      object === undefined
        ? undefined
        : {
            bucket: textOf(object["bucket"]),
            path: textOf(object["path"]),
            mimeType: textOf(object["mimeType"]),
            status: textOf(object["status"]),
          },
    previews: isRecord(row["previews"])
      ? previewsOf(row["previews"], "drive_link")
      : undefined,
  };
}

export function previewsOf(value: unknown, fn: string): DrivePreviews {
  const row = recordOf(value, fn);

  return {
    attachmentId: textOf(row["attachmentId"]),
    bucket: textOf(row["bucket"]),
    pages: Number(row["pages"]),
    prefix: textOf(row["prefix"]),
    paths: Array.isArray(row["paths"]) ? row["paths"].map(textOf) : [],
  };
}

function optionalCount(value: unknown): number | undefined {
  return value === null || value === undefined ? undefined : Number(value);
}

export function objectsOf(value: unknown): DriveStoredObject[] {
  return recordsOf(value, "drive_prune").map((row) => ({
    bucket: textOf(row["bucket"]),
    path: textOf(row["path"]),
  }));
}

/**
 * `drive_create_file` for `contribute`: `{ node, attachment }` for a caller who
 * can read the folder, `{ id, attachment }` for one who may only add files.
 */
export function contributionOf(
  value: unknown,
  fn: string,
): { readonly id: string; readonly attachment: Attachment } {
  const row = recordOf(value, fn);
  const node = isRecord(row["node"]) ? row["node"] : row;

  return {
    id: textOf(node["id"]),
    attachment: attachmentOf(recordOf(row["attachment"], fn)),
  };
}

/** `drive_commit` for `commitContribution`: a node, or `{ id, attachmentId }`. */
export function committedOf(value: unknown): {
  readonly id: string;
  readonly attachmentId: string;
} {
  const row = recordOf(value, "drive_commit");

  return { id: textOf(row["id"]), attachmentId: textOf(row["attachmentId"]) };
}

/** `drive_link_upload`; `undefined` while the link wants its password. */
export function requestUploadOf(
  value: unknown,
): { readonly id: string; readonly attachment: Attachment } | undefined {
  const row = recordOf(value, "drive_link_upload");

  if (row["passwordRequired"] === true) {
    return undefined;
  }

  return {
    id: textOf(row["nodeId"]),
    attachment: attachmentOf(recordOf(row["attachment"], "drive_link_upload")),
  };
}

/** The methods whose result holds nodes, which `fields` parses. */
const NODE_METHODS = [
  "createFolder",
  "get",
  "list",
  "shared",
  "rename",
  "move",
  "hold",
  "releaseHold",
  "lock",
  "unlock",
  "blockDownloads",
  "upload",
  "uploadRevision",
  "commit",
  "restoreRevision",
  "restore",
  "bin",
  "open",
  "starred",
  "recent",
  "link",
  "label",
  "labeled",
] as const satisfies readonly (keyof Drive)[];

const isNode = (value: Readonly<Record<string, unknown>>): boolean =>
  typeof value["kind"] === "string" &&
  typeof value["organizationId"] === "string";

/**
 * `value` with the `fields` of every node in it parsed: a node, a list, or `{
 * node, children }`.
 */
async function parseNodes(
  fields: BlockFields<object>,
  value: unknown,
): Promise<Result<unknown>> {
  if (Array.isArray(value)) {
    const out: unknown[] = [];

    for (const item of value) {
      const parsed = await parseNodes(fields, item);

      if (!parsed.ok) {
        return parsed;
      }

      out.push(parsed.data);
    }

    return ok(out);
  }

  if (!isRecord(value)) {
    return ok(value);
  }

  const extra = value["fields"];

  if (isNode(value) && isRecord(extra)) {
    const parsed = await fields.read({ ...extra });

    return parsed.ok ? ok({ ...value, fields: parsed.data }) : parsed;
  }

  const out: Record<string, unknown> = { ...value };

  for (const key of ["node", "children"]) {
    if (value[key] === undefined) {
      continue;
    }

    const parsed = await parseNodes(fields, value[key]);

    if (!parsed.ok) {
      return parsed;
    }

    out[key] = parsed.data;
  }

  return ok(out);
}

/**
 * The client with `fields` applied: the extra fields of a new folder or file
 * are validated first, and every node it returns is parsed.
 */
export function withFields<F extends object>(
  client: Drive,
  fields: BlockFields<object>,
): Drive<F> {
  const out: Drive = { ...client };

  for (const method of NODE_METHODS) {
    // SAFETY: every listed method returns an AsyncResult; the arguments are
    // passed through unchanged.
    const original = client[method] as (
      ...args: unknown[]
    ) => AsyncResult<unknown>;

    const wrapped = (...args: unknown[]): AsyncResult<unknown> => {
      const input = args[1];

      const extra =
        (method === "createFolder" || method === "upload") && isRecord(input)
          ? input["fields"]
          : undefined;

      const checked = isRecord(extra)
        ? AsyncResult.from(() => fields.write({ ...extra })).map(() => true)
        : AsyncResult.ok(true);

      return checked
        .andThen(() => original.apply(client, args))
        .andThen((value) => parseNodes(fields, value));
    };

    Object.defineProperty(out, method, {
      value: wrapped,
      enumerable: true,
      configurable: true,
      writable: true,
    });
  }

  // SAFETY: `out` has every member of `client`, and the node methods return
  // the same shapes with `fields` parsed by the schema F describes.
  return out as Drive<F>;
}
