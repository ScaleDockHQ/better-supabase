import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { Result } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { ApprovalStatus } from "../approvals/approvals.ts";
import type {
  Attachment,
  AttachmentDownload,
  Attachments,
  AttachmentStorage,
} from "../attachments/attachments.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { DriveDocument, DriveDocuments } from "./documents.ts";
import type {
  DriveContribution,
  DriveFileRequest,
  DriveRequestUpload,
} from "./requests.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { attachmentOf, stored } from "../attachments/attachments.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";
import { claimsUploads, claimUpload } from "../upload-claim.ts";
import { driveDocuments } from "./documents.ts";
import {
  KINDS,
  approvalOf,
  batchOf,
  binEntryOf,
  committedOf,
  connectionOf,
  contributionOf,
  connectionsOf,
  driveGrantOf,
  driveOf,
  drivesOf,
  grantOf,
  linkOf,
  nodeOf,
  nodesOf,
  objectsOf,
  previewsOf,
  requestUploadOf,
  revisionOf,
  withFields,
} from "./parse.ts";
import { putRequestFile } from "./requests.ts";

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
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the nodes' extra columns
   * (`blocks.drive.options.extraColumns`), keyed by column name. It types and
   * parses `fields` on every node the client returns, and validates them on
   * `createFolder` and `upload`.
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

/**
 * A folder or a file. `F` types the extra columns the `fields` schema
 * describes.
 */
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
  /**
   * The file's current attachment; `undefined` for a folder or a file not
   * uploaded yet.
   */
  readonly attachmentId: string | undefined;
  readonly file: DriveFile | undefined;
  /** The `extraColumns` values, by column name. */
  readonly fields: Readonly<Record<string, unknown>> & F;
  /**
   * The caller's role on the node, direct or inherited, where the call reports
   * it.
   */
  readonly role: string | undefined;
  /** The drive the node is in, with `blocks.drive.options.drives`. */
  readonly driveId: string | undefined;
  /** `internal`, or the provider of a connected drive's mirror. */
  readonly source: string;
  /** The provider's id, on a mirror of a connected drive. */
  readonly externalId: string | undefined;
  /** The provider's metadata, on a mirror of a connected drive. */
  readonly externalMetadata: Readonly<Record<string, unknown>> | undefined;
  /** Set while the node is under a legal hold. */
  readonly legalHoldUntil: Temporal.Instant | undefined;
  /** A mirror of an external account, which only the sync may change. */
  readonly readOnly: boolean;
  /** The node or something under it is under a legal hold. */
  readonly held: boolean;
  /** The user who checked the file out, while the lock is live. */
  readonly lockedBy: string | undefined;
  /** When the check-out lock ends, while it is live. */
  readonly lockedUntil: Temporal.Instant | undefined;
  readonly lockNote: string | undefined;
  /** Downloads are blocked on this node itself (folders above may block too). */
  readonly downloadBlocked: boolean;
  /**
   * Whether the caller may download the file's original, where the call reports
   * it. A download block on the node, a folder above or the drive keeps it back
   * from callers below the write role.
   */
  readonly downloadable: boolean | undefined;
  /** How many preview pages the renderer stored for the current content. */
  readonly previewPages: number | undefined;
  readonly starredAt: Temporal.Instant | undefined;
  readonly openedAt: Temporal.Instant | undefined;
  /** The tags on the node, with the tags block installed. */
  readonly labels: readonly DriveLabel[] | undefined;
  /**
   * The latest approval request for the file's current version, with the
   * approvals block installed; `undefined` when there is none.
   */
  readonly approval: DriveApprovalState | undefined;
  /** The file's document control, with `options.control`. */
  readonly document: DriveDocument | undefined;
}

/** A tag on a node. */
export interface DriveLabel {
  readonly id: string;
  readonly name: string;
  readonly color: string | undefined;
}

export interface DriveApprovalState {
  readonly id: string;
  readonly status: ApprovalStatus;
  readonly createdAt: Temporal.Instant;
  readonly decidedAt: Temporal.Instant | undefined;
}

/** An approval request for one stored version of a file. */
export interface DriveApproval extends DriveApprovalState {
  /** The attachment the request is for. */
  readonly attachmentId: string;
  /** Its revision number, with the versions block installed. */
  readonly revision: number | undefined;
  /** Whether that version is the file's content now. */
  readonly current: boolean;
  readonly step: number;
  readonly reason: string | undefined;
  readonly requestedBy: string | undefined;
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

/** A drive of an organization, with the caller's role on it. */
export interface DriveDrive {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  /** One of `blocks.drive.options.driveKinds`. */
  readonly kind: string;
  readonly ownerId: string | undefined;
  /** The external account this drive mirrors, with drives enabled. */
  readonly connectionId: string | undefined;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant | undefined;
  readonly role: string | undefined;
  /** A connected drive, which only the sync may change. */
  readonly readOnly: boolean;
  /** Downloads are blocked for every node in the drive. */
  readonly downloadBlocked: boolean;
}

/** A drive-level grant, inherited by every node in the drive. */
export interface DriveDriveGrant {
  readonly id: string;
  readonly driveId: string;
  readonly principal: DrivePrincipal;
  readonly role: string;
  readonly expiresAt: Temporal.Instant | undefined;
}

/** An external account whose drive the organization mirrors. */
export interface DriveConnection {
  readonly id: string;
  readonly organizationId: string;
  readonly userId: string | undefined;
  /** One of `blocks.drive.options.sources`. */
  readonly provider: string;
  readonly name: string;
  readonly status: string;
  readonly syncCursor: string | undefined;
  readonly lastSyncedAt: Temporal.Instant | undefined;
  readonly lastSyncError: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant | undefined;
}

/** A new drive: a shared one, or a mirror of a connection. */
export interface NewDrive {
  readonly name: string;
  /** One of `blocks.drive.options.driveKinds`; default the first. */
  readonly kind?: string;
  /** Default the caller; needs the manage permission to name another member. */
  readonly ownerId?: string;
  /** The connection to mirror; its user owns the drive. */
  readonly connectionId?: string;
}

export interface NewDriveFolder<F extends object = Record<never, never>> {
  readonly parentId?: string | null;
  /**
   * The drive for a top-level folder, with `blocks.drive.options.drives`; a
   * child folder stays in its parent's drive.
   */
  readonly driveId?: string | null;
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
    /**
     * Whether the link hands out the original: its `download_allowed` flag, and
     * no download block on the item.
     */
    readonly downloadAllowed: boolean;
  };
  readonly node: DriveNode<F>;
  /** A folder's children; `undefined` for a file. */
  readonly children: readonly DriveNode<F>[] | undefined;
  /**
   * A file's object, for the server to sign a download URL with; `undefined`
   * when the link doesn't allow downloads.
   */
  readonly object:
    | {
        readonly bucket: string;
        readonly path: string;
        readonly mimeType: string;
        readonly status: string;
      }
    | undefined;
  /** A file's rendered pages, which a download block leaves visible. */
  readonly previews: DrivePreviews | undefined;
}

/**
 * The rendered pages of a file's current content, stored in `bucket` at
 * `<previewPrefix>/<organization>/<node>/<attachment>/<page>`.
 */
export interface DrivePreviews {
  readonly attachmentId: string;
  readonly bucket: string;
  readonly pages: number;
  /** The folder the pages live in: `<prefix>/<page>`, from 1. */
  readonly prefix: string;
  readonly paths: readonly string[];
}

export interface DriveStoredObject {
  readonly bucket: string;
  readonly path: string;
}

export interface DrivePage {
  readonly pageSize?: number;
}

/** `F` types the nodes' extra columns, from the `fields` schema. */
export interface Drive<
  F extends object = Record<never, never>,
> extends DriveDocuments<DriveNode<F>> {
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
      /** A top-level listing of one drive, with drives enabled. */
      readonly driveId?: string | null;
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
    options?: {
      readonly rank?: string;
      readonly conflict?: DriveConflict;
      /** The drive to move into when `parentId` is `null`. */
      readonly driveId?: string | null;
    },
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
  /** Places a legal hold on the node and everything under it. */
  hold(id: string, until: Temporal.Instant): AsyncResult<DriveNode<F>>;
  releaseHold(id: string): AsyncResult<DriveNode<F>>;
  /**
   * Checks the file out: until `until` (default 8 hours, at most 30 days)
   * nobody else may upload, commit, rename, move, trash or delete it.
   */
  lock(
    id: string,
    options?: { readonly until?: Temporal.Instant; readonly note?: string },
  ): AsyncResult<DriveNode<F>>;
  /** Ends the check-out; `force` lets the share role end someone else's. */
  unlock(
    id: string,
    options?: { readonly force?: boolean },
  ): AsyncResult<DriveNode<F>>;
  /**
   * Blocks (or allows) downloads of the node and everything under it for
   * callers below the write role. Previews stay readable.
   */
  blockDownloads(id: string, blocked?: boolean): AsyncResult<DriveNode<F>>;
  /** Blocks (or allows) downloads for every node in a drive. */
  blockDriveDownloads(id: string, blocked?: boolean): AsyncResult<DriveDrive>;
  /** The rendered pages of a file's current content. */
  previews(id: string): AsyncResult<DrivePreviews>;
  /** Signed URLs for a file's preview pages, first page first. */
  previewUrls(
    id: string,
    options?: { readonly expiresIn?: number },
  ): AsyncResult<readonly string[]>;
  /** The drives of an organization the caller can read. */
  drives(
    organizationId: string,
    options?: DrivePage & { readonly skip?: number },
  ): AsyncResult<readonly DriveDrive[]>;
  drive(id: string): AsyncResult<DriveDrive>;
  createDrive(organizationId: string, drive: NewDrive): AsyncResult<DriveDrive>;
  renameDrive(id: string, name: string): AsyncResult<DriveDrive>;
  /** Deletes the drive and every node in it; fails under a legal hold. */
  deleteDrive(id: string): AsyncResult<boolean>;
  shareDrive(
    id: string,
    principal: DrivePrincipal,
    role: string,
    options?: { readonly expiresAt?: Temporal.Instant },
  ): AsyncResult<DriveDriveGrant>;
  unshareDrive(id: string, principal: DrivePrincipal): AsyncResult<boolean>;
  /** The drive's grants, which every node in it inherits. */
  driveGrants(id: string): AsyncResult<readonly DriveDriveGrant[]>;
  /** The caller's connections to external accounts, newest names last. */
  connections(
    organizationId: string,
    options?: DrivePage,
  ): AsyncResult<readonly DriveConnection[]>;
  connect(
    organizationId: string,
    provider: string,
    name: string,
  ): AsyncResult<DriveConnection>;
  disconnect(id: string): AsyncResult<boolean>;
  /**
   * Creates the file (or a revision, with `conflict: "replace"`) and a signed
   * upload URL.
   */
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
  /**
   * Adds a file to a folder for a caller with only `options.uploadRole` on it.
   * The file takes a free name, and the result names it without its content. A
   * caller with the write role gets the same result.
   */
  contribute(
    organizationId: string,
    file: {
      readonly parentId: string;
      readonly name: string;
      readonly mimeType: string;
      readonly size: number;
    },
  ): AsyncResult<DriveContribution>;
  /** Confirms a contribution's upload, or a new revision of one. */
  commitContribution(
    id: string,
    attachmentId: string,
  ): AsyncResult<{ readonly id: string; readonly attachmentId: string }>;
  /**
   * Creates a file request on a folder: a share link with role `upload` that
   * lets anyone holding the token send files into it. Needs the share role.
   */
  createFileRequest(
    folderId: string,
    options?: {
      readonly expiresAt?: Temporal.Instant;
      readonly maxUses?: number;
      readonly password?: string;
    },
  ): AsyncResult<DriveFileRequest>;
  /**
   * Server only, on a client made with the service transport and storage: sends
   * one file through a file request token, uploads it and commits it. Each call
   * counts one use of the link.
   */
  uploadToRequest(
    token: string,
    file: Blob,
    options: {
      readonly name: string;
      /** Default: the blob's type. */
      readonly mimeType?: string;
      readonly password?: string;
    },
  ): AsyncResult<DriveRequestUpload>;
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
  /**
   * What a share link token opens; `nodeId` picks an item under a linked
   * folder.
   */
  link(
    token: string,
    options?: { readonly nodeId?: string },
  ): AsyncResult<DriveLinkView<F>>;
  /** Puts a tag on the node as a label, or takes it off (`applied: false`). */
  label(
    id: string,
    tagId: string,
    applied?: boolean,
  ): AsyncResult<DriveNode<F>>;
  /** The nodes that carry a label and the caller can read, folders first. */
  labeled(
    organizationId: string,
    tagId: string,
    options?: DrivePage,
  ): AsyncResult<readonly DriveNode<F>[]>;
  /**
   * Asks for approval of one version of a file: `attachmentId`, or the current
   * one. The request stays with those bytes.
   */
  requestApproval(
    id: string,
    options?: { readonly attachmentId?: string; readonly reason?: string },
  ): AsyncResult<DriveApproval>;
  /** The file's approval requests, newest first. */
  approvals(id: string): AsyncResult<readonly DriveApproval[]>;
  /**
   * Service role: deletes revisions' files no revision or node uses any more,
   * and removes their objects through `storage`.
   */
  prune(options?: {
    readonly maxObjects?: number;
  }): AsyncResult<readonly DriveStoredObject[]>;
}

/** The `drive` SQL module as typed calls, as the caller. */
const CLAIM_HINTS = {
  notUploaded: "ATTACHMENT_NOT_UPLOADED",
  forbidden: "DRIVE_FORBIDDEN",
} as const;

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
    if (storage === undefined) {
      return AsyncResult.err(noStorage());
    }

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

  const claimed = (attachmentId: string): AsyncResult<unknown> =>
    storage === undefined || !claimsUploads(storage)
      ? AsyncResult.ok(undefined)
      : call("get_attachment", { id: attachmentId }, (value) =>
          isRecord(value) ? attachmentOf(value) : undefined,
        ).andThen((attachment) =>
          attachment === undefined || attachment.uploadedAt !== undefined
            ? AsyncResult.ok(undefined)
            : claimUpload(storage, attachment, CLAIM_HINTS),
        );

  const page = (
    fn: string,
    args: Record<string, unknown>,
  ): AsyncResult<readonly DriveNode[]> =>
    call(fn, args, (value) => nodesOf(value, fn));

  const client: Drive = {
    ...driveDocuments(call, nodeOf, nodesOf),
    createFolder: (organizationId, folder) =>
      call(
        "drive_create_folder",
        {
          tenant: organizationId,
          parent: folder.parentId ?? null,
          name: folder.name,
          conflict: folder.conflict ?? null,
          fields: folder.fields ?? null,
          drive: folder.driveId ?? null,
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
        drive: list.driveId ?? null,
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
          drive: move.driveId ?? null,
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
    hold: (id, until) =>
      call("drive_hold", { node: id, until: until.toString() }, (value) =>
        nodeOf(value, "drive_hold"),
      ),
    releaseHold: (id) =>
      call("drive_release_hold", { node: id }, (value) =>
        nodeOf(value, "drive_release_hold"),
      ),
    lock: (id, lock = {}) =>
      call(
        "drive_lock",
        {
          node: id,
          until: lock.until?.toString() ?? null,
          note: lock.note ?? null,
        },
        (value) => nodeOf(value, "drive_lock"),
      ),
    unlock: (id, unlock = {}) =>
      call(
        "drive_unlock",
        { node: id, force: unlock.force ?? false },
        (value) => nodeOf(value, "drive_unlock"),
      ),
    blockDownloads: (id, blocked = true) =>
      call(
        "drive_set_download_blocked",
        { target_type: "node", target_id: id, blocked },
        (value) => nodeOf(value, "drive_set_download_blocked"),
      ),
    blockDriveDownloads: (id, blocked = true) =>
      call(
        "drive_set_download_blocked",
        { target_type: "drive", target_id: id, blocked },
        (value) => driveOf(value, "drive_set_download_blocked"),
      ),
    previews: (id) =>
      call("drive_previews", { node: id }, (value) =>
        previewsOf(value, "drive_previews"),
      ),
    previewUrls: (id, urls = {}) => {
      if (storage === undefined) {
        return AsyncResult.err(noStorage());
      }

      return client.previews(id).andThen(async (previews) => {
        const signedUrls: string[] = [];

        for (const path of previews.paths) {
          const url = await stored(
            storage
              .from(previews.bucket)
              .createSignedUrl(path, urls.expiresIn ?? 3600),
          );

          if (!url.ok) {
            return url;
          }

          signedUrls.push(url.data.signedUrl);
        }

        return ok(signedUrls);
      });
    },
    drives: (organizationId, list = {}) =>
      call(
        "drive_list_drives",
        {
          tenant: organizationId,
          page_size: list.pageSize ?? null,
          skip: list.skip ?? null,
        },
        (value) => drivesOf(value, "drive_list_drives"),
      ),
    drive: (id) =>
      call("drive_get_drive", { drive: id }, (value) =>
        driveOf(value, "drive_get_drive"),
      ),
    createDrive: (organizationId, drive) =>
      call(
        "drive_create_drive",
        {
          tenant: organizationId,
          name: drive.name,
          kind: drive.kind ?? null,
          owner: drive.ownerId ?? null,
          connection: drive.connectionId ?? null,
        },
        (value) => driveOf(value, "drive_create_drive"),
      ),
    renameDrive: (id, name) =>
      call("drive_rename_drive", { drive: id, name }, (value) =>
        driveOf(value, "drive_rename_drive"),
      ),
    deleteDrive: (id) =>
      call("drive_delete_drive", { drive: id }, (value) => value === true),
    shareDrive: (id, principal, role, share = {}) =>
      call(
        "drive_share_drive",
        {
          drive: id,
          principal_type: principal.type,
          principal_id: principal.id,
          role,
          expires_at: share.expiresAt?.toString() ?? null,
        },
        (value) => driveGrantOf(value, "drive_share_drive"),
      ),
    unshareDrive: (id, principal) =>
      call(
        "drive_unshare_drive",
        {
          drive: id,
          principal_type: principal.type,
          principal_id: principal.id,
        },
        (value) => value === true,
      ),
    driveGrants: (id) =>
      call("drive_grants_for_drive", { drive: id }, (value) =>
        recordsOf(value, "drive_grants_for_drive").map((row) =>
          driveGrantOf(row, "drive_grants_for_drive"),
        ),
      ),
    connections: (organizationId, list = {}) =>
      call(
        "drive_list_connections",
        { tenant: organizationId, page_size: list.pageSize ?? null },
        (value) => connectionsOf(value, "drive_list_connections"),
      ),
    connect: (organizationId, provider, name) =>
      call(
        "drive_connect",
        { tenant: organizationId, provider, name },
        (value) => connectionOf(value, "drive_connect"),
      ),
    disconnect: (id) =>
      call("drive_disconnect", { connection: id }, (value) => value === true),
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
            drive: file.driveId ?? null,
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
      claimed(attachmentId).andThen(() =>
        call("drive_commit", { node: id, attachment: attachmentId }, (value) =>
          nodeOf(value, "drive_commit"),
        ),
      ),
    contribute: (organizationId, file) => {
      if (storage === undefined) {
        return AsyncResult.err(noStorage());
      }

      return call(
        "drive_create_file",
        {
          tenant: organizationId,
          parent: file.parentId,
          name: file.name,
          mime_type: file.mimeType,
          size: file.size,
          conflict: "rename",
          fields: null,
          drive: null,
        },
        (value) => contributionOf(value, "drive_create_file"),
      ).andThen(({ id, attachment }) =>
        stored(
          storage
            .from(attachment.bucket)
            .createSignedUploadUrl(attachment.path),
        ).map((url) => ({
          id,
          attachment,
          signedUrl: url.signedUrl,
          token: url.token,
        })),
      );
    },
    commitContribution: (id, attachmentId) =>
      claimed(attachmentId).andThen(() =>
        call(
          "drive_commit",
          { node: id, attachment: attachmentId },
          committedOf,
        ),
      ),
    createFileRequest: (folderId, request = {}) =>
      call(
        "drive_request_files",
        {
          folder: folderId,
          expires_at: request.expiresAt?.toString() ?? null,
          max_uses: request.maxUses ?? null,
          password: request.password ?? null,
        },
        (value) => {
          const row = recordOf(value, "drive_request_files");

          return { id: textOf(row["id"]), token: textOf(row["token"]) };
        },
      ),
    uploadToRequest: (token, file, upload) => {
      if (storage === undefined) {
        return AsyncResult.err(noStorage());
      }

      return call(
        "drive_link_upload",
        {
          token,
          name: upload.name,
          mime_type:
            upload.mimeType ?? (file.type || "application/octet-stream"),
          size: file.size,
          password: upload.password ?? null,
        },
        requestUploadOf,
      ).andThen(async (pending): Promise<Result<DriveRequestUpload>> => {
        if (pending === undefined) {
          return ok({ passwordRequired: true });
        }

        const sent = await putRequestFile(storage, pending.attachment, file);

        if (!sent.ok) {
          return sent;
        }

        return client
          .commitContribution(pending.id, pending.attachment.id)
          .map((committed): DriveRequestUpload => ({
            passwordRequired: false,
            ...committed,
          }));
      });
    },
    download: (id, download = {}) => {
      if (attachments === undefined) {
        return AsyncResult.err(noAttachments());
      }

      return client.get(id).andThen((node) => {
        if (node.attachmentId === undefined) {
          return Promise.resolve(
            err(
              dbError("invalid_request", "This item has no content", {
                hint: "DRIVE_NOT_A_FILE",
              }),
            ),
          );
        }

        if (node.downloadable === false) {
          return Promise.resolve(
            err(
              dbError("forbidden", "Downloads of this file are blocked", {
                hint: "DRIVE_DOWNLOAD_BLOCKED",
              }),
            ),
          );
        }

        return attachments.download(
          node.document?.effectiveOnly === true
            ? (node.document.effectiveAttachmentId ?? node.attachmentId)
            : node.attachmentId,
          download,
        );
      });
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
    label: (id, tagId, applied = true) =>
      call("drive_label", { node: id, tag: tagId, applied }, (value) =>
        nodeOf(value, "drive_label"),
      ),
    labeled: (organizationId, tagId, list = {}) =>
      page("drive_labeled", {
        tenant: organizationId,
        tag: tagId,
        page_size: list.pageSize ?? null,
      }),
    requestApproval: (id, request = {}) =>
      call(
        "drive_request_approval",
        {
          node: id,
          attachment: request.attachmentId ?? null,
          reason: request.reason ?? null,
        },
        (value) => approvalOf(value, "drive_request_approval"),
      ),
    approvals: (id) =>
      call("drive_approvals", { node: id }, (value) =>
        recordsOf(value, "drive_approvals").map((row) =>
          approvalOf(row, "drive_approvals"),
        ),
      ),
    link: (token, link = {}) =>
      call("drive_link", { token, node: link.nodeId ?? null }, linkOf),
    prune: (prune = {}) =>
      call(
        "drive_prune",
        { max_objects: prune.maxObjects ?? null },
        objectsOf,
      ).andThen(async (objects) => {
        if (storage === undefined || objects.length === 0) {
          return ok(objects);
        }

        const buckets = Map.groupBy(objects, (object) => object.bucket);

        for (const [bucket, inBucket] of buckets) {
          const removed = await stored(
            storage.from(bucket).remove(inBucket.map((object) => object.path)),
          );

          if (!removed.ok) {
            return removed;
          }
        }

        return ok(objects);
      }),
  };

  return withBlockHooks(
    withFields<FieldsOf<S>>(client, fields),
    options.hooks,
    { block: "drive", ...(options.logger ? { logger: options.logger } : {}) },
  );
}
