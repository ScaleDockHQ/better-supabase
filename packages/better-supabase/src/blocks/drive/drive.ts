import type { SubjectConfig } from "../../config/types/subjects.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";

import {
  type BlockFields,
  blockFields,
  type FieldsOf,
} from "../../core/block-fields.ts";
import { DEFAULT_BLOCK_SCHEMA } from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok, type Result } from "../../core/result.ts";
import {
  type Attachment,
  type AttachmentDownload,
  type Attachments,
  type AttachmentStorage,
  attachmentOf,
  stored,
} from "../attachments/attachments.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface DriveOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  /** The caller's transport (`rpcTransport(supabase)`), so grants apply. */
  readonly transport: BlockTransport;
  /** The caller's `supabase.storage`, for upload URLs and removing purged files. */
  readonly storage?: AttachmentStorage;
  /**
   * The `attachments` port: the attachments block over the same transport,
   * which downloads the files. `createBlocks` passes it.
   */
  readonly attachments?: Pick<Attachments, "download">;
  /** The module schema, or its API schema: `defineBlocks` passes it from `blocks.generated.ts`. */
  readonly schema?: string;
  /**
   * A Standard Schema for the nodes' extra columns
   * (`blocks.drive.options.extraColumns`), keyed by column name. It types
   * and parses `fields` on every node the client returns, and validates
   * them on `createFolder` and `upload`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Drive<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

export type DriveNodeKind = "folder" | "file";
/** What happens when the name is taken in the folder. */
export type DriveConflict = "fail" | "rename" | "replace";
export type DrivePrincipalType = "user" | "team" | "role";

/** A file's stored content, from its current attachment. */
export interface DriveFile {
  readonly mimeType: string;
  readonly size: number;
  readonly status: string;
  readonly uploadedAt: Temporal.Instant | undefined;
}

/** A folder or a file. `F` types the extra columns the `fields` schema describes. */
export interface DriveNode<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly parentId: string | null;
  readonly kind: DriveNodeKind;
  readonly name: string;
  readonly rank: string | undefined;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant | undefined;
  /** Set while the node is in the bin. */
  readonly deletedAt: Temporal.Instant | undefined;
  /** The file's current attachment; `undefined` for a folder or a file not uploaded yet. */
  readonly attachmentId: string | undefined;
  readonly file: DriveFile | undefined;
  /** The `extraColumns` values, by column name. */
  readonly fields: Readonly<Record<string, unknown>> & F;
  /** The caller's role on the node, direct or inherited, where the call reports it. */
  readonly role: string | undefined;
  readonly starredAt: Temporal.Instant | undefined;
  readonly openedAt: Temporal.Instant | undefined;
}

/** A folder above a node, root first. */
export interface DriveCrumb {
  readonly id: string;
  readonly name: string;
  readonly kind: DriveNodeKind;
}

export interface DrivePrincipal {
  readonly type: DrivePrincipalType;
  /** A user id, a team id or a membership role. */
  readonly id: string;
}

export interface DriveGrant {
  readonly id: string;
  readonly nodeId: string;
  readonly principal: DrivePrincipal;
  readonly role: string;
  readonly expiresAt: Temporal.Instant | undefined;
  /** Granted on a folder above the node. */
  readonly inherited: boolean;
}

export interface NewDriveFolder<F extends object = Record<never, never>> {
  readonly parentId?: string | null;
  readonly name: string;
  readonly conflict?: DriveConflict;
  /** Values for `extraColumns`; unset ones are copied from the parent. */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

export interface NewDriveFile<
  F extends object = Record<never, never>,
> extends NewDriveFolder<F> {
  readonly mimeType: string;
  /** Bytes; `commit` replaces it with the stored size. */
  readonly size: number;
}

/** A pending upload: PUT the bytes to `signedUrl`, then call `commit`. */
export interface DriveUpload<F extends object = Record<never, never>> {
  readonly node: DriveNode<F>;
  readonly attachment: Attachment;
  readonly signedUrl: string;
  readonly token: string;
}

export interface DriveRevision {
  readonly id: string;
  readonly number: number;
  readonly label: string | undefined;
  readonly source: string;
  readonly attachmentId: string;
  readonly name: string;
  readonly mimeType: string;
  readonly size: number;
  /** The revision the file shows now. */
  readonly current: boolean;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
}

export interface DriveBatch {
  /** The trash item of the node that was moved to the bin. */
  readonly id: string;
  readonly batchId: string;
  /** The node and everything under it. */
  readonly count: number;
}

export interface DriveBinEntry<
  F extends object = Record<never, never>,
> extends DriveBatch {
  readonly node: DriveNode<F>;
  readonly trashedBy: string | undefined;
  readonly trashedAt: Temporal.Instant;
  readonly purgeAfter: Temporal.Instant | undefined;
}

/** What a share link opens. */
export interface DriveLinkView<F extends object = Record<never, never>> {
  readonly link: {
    readonly id: string;
    readonly role: string;
    readonly nodeId: string;
    readonly expiresAt: Temporal.Instant | undefined;
  };
  readonly node: DriveNode<F>;
  /** A folder's children; `undefined` for a file. */
  readonly children: readonly DriveNode<F>[] | undefined;
  /** A file's object, for the server to sign a download URL with. */
  readonly object:
    | {
        readonly bucket: string;
        readonly path: string;
        readonly mimeType: string;
        readonly status: string;
      }
    | undefined;
}

export interface DriveStoredObject {
  readonly bucket: string;
  readonly path: string;
}

export interface DrivePage {
  readonly pageSize?: number;
}

/** `F` types the nodes' extra columns, from the `fields` schema. */
export interface Drive<F extends object = Record<never, never>> {
  createFolder(
    organizationId: string,
    folder: NewDriveFolder<F>,
  ): AsyncResult<DriveNode<F>>;
  get(id: string): AsyncResult<DriveNode<F>>;
  /** A folder's children (the root without `parentId`), folders first. */
  list(
    organizationId: string,
    options?: DrivePage & {
      readonly parentId?: string | null;
      readonly skip?: number;
    },
  ): AsyncResult<readonly DriveNode<F>[]>;
  /** Nodes shared with the caller directly, outside folders they can open. */
  shared(
    organizationId: string,
    options?: DrivePage,
  ): AsyncResult<readonly DriveNode<F>[]>;
  /** The node's folders, root first, for breadcrumbs. */
  path(id: string): AsyncResult<readonly DriveCrumb[]>;
  rename(
    id: string,
    name: string,
    options?: { readonly conflict?: DriveConflict },
  ): AsyncResult<DriveNode<F>>;
  /** Moves into `parentId` (`null` for the root), optionally to a rank key. */
  move(
    id: string,
    parentId: string | null,
    options?: { readonly rank?: string; readonly conflict?: DriveConflict },
  ): AsyncResult<DriveNode<F>>;
  /** Deletes the node and everything under it for good. */
  delete(id: string): AsyncResult<boolean>;
  share(
    id: string,
    principal: DrivePrincipal,
    role: string,
    options?: { readonly expiresAt?: Temporal.Instant },
  ): AsyncResult<DriveGrant>;
  unshare(id: string, principal: DrivePrincipal): AsyncResult<boolean>;
  /** The node's grants, inherited ones included. */
  grants(id: string): AsyncResult<readonly DriveGrant[]>;
  /** Creates the file (or a revision, with `conflict: "replace"`) and a signed upload URL. */
  upload(
    organizationId: string,
    file: NewDriveFile<F>,
  ): AsyncResult<DriveUpload<F>>;
  /** A signed upload URL for a new revision of a file. */
  uploadRevision(
    id: string,
    file: { readonly mimeType: string; readonly size: number },
  ): AsyncResult<DriveUpload<F>>;
  /** Confirms an upload and makes it the file's content. */
  commit(id: string, attachmentId: string): AsyncResult<DriveNode<F>>;
  /** A signed URL for the file's current content, behind the scan gate. */
  download(
    id: string,
    options?: { readonly as?: string | boolean },
  ): AsyncResult<AttachmentDownload>;
  revisions(id: string): AsyncResult<readonly DriveRevision[]>;
  restoreRevision(id: string, revisionId: string): AsyncResult<DriveNode<F>>;
  /** Moves the node and everything under it to the bin. */
  trash(id: string): AsyncResult<DriveBatch>;
  /** Restores a bin entry, renaming it when the name is taken now. */
  restore(
    binId: string,
    options?: { readonly conflict?: DriveConflict },
  ): AsyncResult<DriveBatch & { readonly node: DriveNode<F> }>;
  /** The bin, newest first: the entries the caller may restore. */
  bin(
    organizationId: string,
    options?: DrivePage & { readonly before?: Temporal.Instant },
  ): AsyncResult<readonly DriveBinEntry<F>[]>;
  /** Deletes a bin entry for good; returns how many nodes went. */
  purge(binId: string): AsyncResult<number>;
  star(id: string, starred?: boolean): AsyncResult<boolean>;
  /** Records the node as opened, for `recent`. */
  open(id: string): AsyncResult<DriveNode<F>>;
  starred(
    organizationId: string,
    options?: DrivePage,
  ): AsyncResult<readonly DriveNode<F>[]>;
  recent(
    organizationId: string,
    options?: DrivePage,
  ): AsyncResult<readonly DriveNode<F>[]>;
  /** What a share link token opens; `nodeId` picks an item under a linked folder. */
  link(
    token: string,
    options?: { readonly nodeId?: string },
  ): AsyncResult<DriveLinkView<F>>;
  /**
   * Service role: deletes revisions' files no revision or node uses any
   * more, and removes their objects through `storage`.
   */
  prune(options?: {
    readonly maxObjects?: number;
  }): AsyncResult<readonly DriveStoredObject[]>;
}

const KINDS: readonly DriveNodeKind[] = ["folder", "file"];
const PRINCIPALS: readonly DrivePrincipalType[] = ["user", "team", "role"];

function fileOf(value: unknown): DriveFile | undefined {
  if (!isRecord(value)) return undefined;
  return {
    mimeType: textOf(value["mimeType"]),
    size: Number(value["size"]),
    status: textOf(value["status"]),
    uploadedAt: optionalInstant(value["uploadedAt"]),
  };
}

function nodeOf(value: unknown, fn: string): DriveNode {
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
    starredAt: optionalInstant(row["starredAt"]),
    openedAt: optionalInstant(row["openedAt"]),
  };
}

const nodesOf = (value: unknown, fn: string): DriveNode[] =>
  recordsOf(value, fn).map((row) => nodeOf(row, fn));

function grantOf(value: unknown, fn: string): DriveGrant {
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

function batchOf(value: unknown, fn: string): DriveBatch {
  const row = recordOf(value, fn);
  return {
    id: textOf(row["id"]),
    batchId: textOf(row["batchId"]),
    count: Number(row["count"]),
  };
}

function revisionOf(value: unknown): DriveRevision {
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

function binEntryOf(value: unknown): DriveBinEntry {
  const row = recordOf(value, "drive_bin");
  return {
    ...batchOf(row, "drive_bin"),
    node: nodeOf(row["node"], "drive_bin"),
    trashedBy: optionalText(row["trashedBy"]),
    trashedAt: requiredInstant(row["trashedAt"], "trashedAt"),
    purgeAfter: optionalInstant(row["purgeAfter"]),
  };
}

function linkOf(value: unknown): DriveLinkView {
  const row = recordOf(value, "drive_link");
  const link = recordOf(row["link"], "drive_link");
  const object = isRecord(row["object"]) ? row["object"] : undefined;
  return {
    link: {
      id: textOf(link["id"]),
      role: textOf(link["role"]),
      nodeId: textOf(link["nodeId"]),
      expiresAt: optionalInstant(link["expiresAt"]),
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
  };
}

function objectsOf(value: unknown): DriveStoredObject[] {
  return recordsOf(value, "drive_prune").map((row) => ({
    bucket: textOf(row["bucket"]),
    path: textOf(row["path"]),
  }));
}

const noAttachments = () =>
  dbError(
    "invalid_request",
    "createDrive needs the attachments block to download files",
    { hint: "DRIVE_ATTACHMENTS_CLIENT" },
  );

const noStorage = () =>
  dbError("invalid_request", "createDrive needs storage for files", {
    hint: "DRIVE_STORAGE_CLIENT",
  });

/** The methods whose result holds nodes, which `fields` parses. */
const NODE_METHODS = [
  "createFolder",
  "get",
  "list",
  "shared",
  "rename",
  "move",
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
] as const satisfies readonly (keyof Drive)[];

const isNode = (value: Readonly<Record<string, unknown>>): boolean =>
  typeof value["kind"] === "string" &&
  typeof value["organizationId"] === "string";

/** `value` with the `fields` of every node in it parsed: a node, a list, or `{ node, children }`. */
async function parseNodes(
  fields: BlockFields<object>,
  value: unknown,
): Promise<Result<unknown>> {
  if (Array.isArray(value)) {
    const out: unknown[] = [];
    for (const item of value) {
      const parsed = await parseNodes(fields, item);
      if (!parsed.ok) return parsed;
      out.push(parsed.data);
    }
    return ok(out);
  }
  if (!isRecord(value)) return ok(value);
  const extra = value["fields"];
  if (isNode(value) && isRecord(extra)) {
    const parsed = await fields.read({ ...extra });
    return parsed.ok ? ok({ ...value, fields: parsed.data }) : parsed;
  }
  const out: Record<string, unknown> = { ...value };
  for (const key of ["node", "children"]) {
    if (value[key] === undefined) continue;
    const parsed = await parseNodes(fields, value[key]);
    if (!parsed.ok) return parsed;
    out[key] = parsed.data;
  }
  return ok(out);
}

/**
 * The client with `fields` applied: the extra fields of a new folder or
 * file are validated first, and every node it returns is parsed.
 */
function withFields<F extends object>(
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

/** The `drive` SQL module as typed calls, as the caller. */
export function createDrive<S extends StandardSchemaV1 | undefined = undefined>(
  options: DriveOptions<S>,
): Drive<FieldsOf<S>> {
  applyTemporal(options);
  const fields: BlockFields<object> = blockFields(
    options.fields,
    "drive node fields",
  );
  const call = blockCall(options.transport, options.schema, options.mappers);
  const storage = options.storage;
  const attachments = options.attachments;

  const signed = (fn: string) => (value: unknown) => {
    const row = recordOf(value, fn);
    return {
      node: nodeOf(row["node"], fn),
      attachment: attachmentOf(row["attachment"]),
    };
  };
  const withUploadUrl = (
    pending: () => AsyncResult<{ node: DriveNode; attachment: Attachment }>,
  ): AsyncResult<DriveUpload> => {
    if (storage === undefined) return AsyncResult.err(noStorage());
    return pending().andThen(({ node, attachment }) =>
      stored(
        storage.from(attachment.bucket).createSignedUploadUrl(attachment.path),
      ).map((url) => ({
        node,
        attachment,
        signedUrl: url.signedUrl,
        token: url.token,
      })),
    );
  };
  const page = (
    fn: string,
    args: Record<string, unknown>,
  ): AsyncResult<readonly DriveNode[]> =>
    call(fn, args, (value) => nodesOf(value, fn));

  const client: Drive = {
    createFolder: (organizationId, folder) =>
      call(
        "drive_create_folder",
        {
          tenant: organizationId,
          parent: folder.parentId ?? null,
          name: folder.name,
          conflict: folder.conflict ?? null,
          fields: folder.fields ?? null,
        },
        (value) => nodeOf(value, "drive_create_folder"),
      ),
    get: (id) =>
      call("drive_get", { node: id }, (value) => nodeOf(value, "drive_get")),
    list: (organizationId, list = {}) =>
      page("drive_list", {
        tenant: organizationId,
        parent: list.parentId ?? null,
        page_size: list.pageSize ?? null,
        skip: list.skip ?? null,
      }),
    shared: (organizationId, list = {}) =>
      page("drive_shared", {
        tenant: organizationId,
        page_size: list.pageSize ?? null,
      }),
    path: (id) =>
      call("drive_path", { node: id }, (value) =>
        recordsOf(value, "drive_path").map((row) => ({
          id: textOf(row["id"]),
          name: textOf(row["name"]),
          kind: enumOrThrow(row["kind"], KINDS, "drive node kind"),
        })),
      ),
    rename: (id, name, rename = {}) =>
      call(
        "drive_rename",
        { node: id, name, conflict: rename.conflict ?? null },
        (value) => nodeOf(value, "drive_rename"),
      ),
    move: (id, parentId, move = {}) =>
      call(
        "drive_move",
        {
          node: id,
          parent: parentId,
          rank: move.rank ?? null,
          conflict: move.conflict ?? null,
        },
        (value) => nodeOf(value, "drive_move"),
      ),
    delete: (id) =>
      call("drive_delete", { node: id }, (value) => value === true),
    share: (id, principal, role, share = {}) =>
      call(
        "drive_share",
        {
          node: id,
          principal_type: principal.type,
          principal_id: principal.id,
          role,
          expires_at: share.expiresAt?.toString() ?? null,
        },
        (value) => grantOf(value, "drive_share"),
      ),
    unshare: (id, principal) =>
      call(
        "drive_unshare",
        {
          node: id,
          principal_type: principal.type,
          principal_id: principal.id,
        },
        (value) => value === true,
      ),
    grants: (id) =>
      call("drive_grants", { node: id }, (value) =>
        recordsOf(value, "drive_grants").map((row) =>
          grantOf(row, "drive_grants"),
        ),
      ),
    upload: (organizationId, file) =>
      withUploadUrl(() =>
        call(
          "drive_create_file",
          {
            tenant: organizationId,
            parent: file.parentId ?? null,
            name: file.name,
            mime_type: file.mimeType,
            size: file.size,
            conflict: file.conflict ?? null,
            fields: file.fields ?? null,
          },
          signed("drive_create_file"),
        ),
      ),
    uploadRevision: (id, file) =>
      withUploadUrl(() =>
        call(
          "drive_upload_revision",
          { node: id, mime_type: file.mimeType, size: file.size },
          signed("drive_upload_revision"),
        ),
      ),
    commit: (id, attachmentId) =>
      call("drive_commit", { node: id, attachment: attachmentId }, (value) =>
        nodeOf(value, "drive_commit"),
      ),
    download: (id, download = {}) => {
      if (attachments === undefined) return AsyncResult.err(noAttachments());
      return client.get(id).andThen((node) =>
        node.attachmentId === undefined
          ? Promise.resolve(
              err(
                dbError("invalid_request", "This item has no content", {
                  hint: "DRIVE_NOT_A_FILE",
                }),
              ),
            )
          : attachments.download(node.attachmentId, download),
      );
    },
    revisions: (id) =>
      call("drive_revisions", { node: id }, (value) =>
        recordsOf(value, "drive_revisions").map(revisionOf),
      ),
    restoreRevision: (id, revisionId) =>
      call(
        "drive_restore_revision",
        { node: id, version: revisionId },
        (value) => nodeOf(value, "drive_restore_revision"),
      ),
    trash: (id) =>
      call("drive_trash", { node: id }, (value) =>
        batchOf(value, "drive_trash"),
      ),
    restore: (binId, restore = {}) =>
      call(
        "drive_restore",
        { item: binId, conflict: restore.conflict ?? null },
        (value) => ({
          ...batchOf(value, "drive_restore"),
          node: nodeOf(
            recordOf(value, "drive_restore")["node"],
            "drive_restore",
          ),
        }),
      ),
    bin: (organizationId, list = {}) =>
      call(
        "drive_bin",
        {
          tenant: organizationId,
          page_size: list.pageSize ?? null,
          before: list.before?.toString() ?? null,
        },
        (value) => recordsOf(value, "drive_bin").map(binEntryOf),
      ),
    purge: (binId) => call("drive_purge", { item: binId }, Number),
    star: (id, starred = true) =>
      call("drive_star", { node: id, starred }, (value) => value === true),
    open: (id) =>
      call("drive_open", { node: id }, (value) => nodeOf(value, "drive_open")),
    starred: (organizationId, list = {}) =>
      page("drive_marked", {
        tenant: organizationId,
        recent: false,
        page_size: list.pageSize ?? null,
      }),
    recent: (organizationId, list = {}) =>
      page("drive_marked", {
        tenant: organizationId,
        recent: true,
        page_size: list.pageSize ?? null,
      }),
    link: (token, link = {}) =>
      call("drive_link", { token, node: link.nodeId ?? null }, linkOf),
    prune: (prune = {}) =>
      call(
        "drive_prune",
        { max_objects: prune.maxObjects ?? null },
        objectsOf,
      ).andThen(async (objects) => {
        if (storage === undefined || objects.length === 0) return ok(objects);
        const buckets = Map.groupBy(objects, (object) => object.bucket);
        for (const [bucket, inBucket] of buckets) {
          const removed = await stored(
            storage.from(bucket).remove(inBucket.map((object) => object.path)),
          );
          if (!removed.ok) return removed;
        }
        return ok(objects);
      }),
  };
  return withBlockHooks(
    withFields<FieldsOf<S>>(client, fields),
    options.hooks,
    {
      block: "drive",
      ...(options.logger ? { logger: options.logger } : {}),
    },
  );
}

/**
 * The `subjects.drive_node` entry for the managed tables, so comments,
 * attachments, versions, trash and search can name drive nodes. The
 * permissions are the tenant-wide floor; grants decide per node.
 */
export function driveSubject(
  options: { readonly schema?: string } = {},
): SubjectConfig {
  return {
    table: `${options.schema ?? DEFAULT_BLOCK_SCHEMA}.drive_nodes`,
    idType: "uuid",
    tenant: "tenant_id",
    title: "name",
    deletedAt: "deleted_at",
    permissions: { read: "drive.read", write: "drive.manage" },
    search: { title: "name" },
  };
}
