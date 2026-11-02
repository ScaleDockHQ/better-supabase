import type { BlockCall } from "../../core/block-helpers.ts";
import type { AttachmentStorage } from "../attachments/attachments.ts";
import type {
  Drive,
  DriveConflict,
  DriveCrumb,
  DriveGrant,
  DriveNode,
  DrivePage,
  DrivePrincipal,
} from "./drive.ts";

import { recordOf } from "../../core/block-helpers.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { firstFailure } from "../read-all.ts";
import { nodesOf } from "./parse.ts";
import { putRequestFile } from "./requests.ts";

/** What the caller may do with one node, from `drive.can`. */
export interface DriveFlags {
  /** The caller's role on the node, direct or inherited. */
  readonly role: string | undefined;
  readonly read: boolean;
  /** Whether the caller may comment on it. */
  readonly comment: boolean;
  /** Whether the caller may download the original. */
  readonly download: boolean;
  /** Whether the caller may add files to it (a folder). */
  readonly upload: boolean;
  readonly write: boolean;
  readonly share: boolean;
}

/** A folder page in one read: `drive.folder`. */
export interface DriveFolderView<F extends object = Record<never, never>> {
  /** `undefined` for the root. */
  readonly node: DriveNode<F> | undefined;
  readonly children: readonly DriveNode<F>[];
  /** The folders above the node, root first; empty at the root. */
  readonly breadcrumbs: readonly DriveCrumb[];
  /** `undefined` at the root, where no node holds the grants. */
  readonly access: DriveFlags | undefined;
  /** The node's grants, inherited ones included; empty at the root. */
  readonly grants: readonly DriveGrant[];
}

/** A grant with the name of its principal, from `drive.grantsWithNames`. */
export interface DriveNamedGrant extends DriveGrant {
  /** What `names` returned for the principal; `undefined` when it knew none. */
  readonly name: string | undefined;
}

/** One grant to give with `drive.shareMany`. */
export interface DriveGrantInput {
  readonly principal: DrivePrincipal;
  readonly role: string;
  readonly expiresAt?: Temporal.Instant;
}

/** Looks up a principal's display name: a member, a team or a role. */
export type DriveNames = (
  principal: DrivePrincipal,
) => string | undefined | Promise<string | undefined>;

/** Reads and helpers that compose the other `Drive` methods. */
export interface DriveHelpers<F extends object = Record<never, never>> {
  /**
   * A folder's page in one call: the node (none at the root), its children, the
   * breadcrumbs, what the caller may do and the grants. The reads run in
   * parallel, and the first failure is the result.
   */
  folder(input: {
    organizationId: string;
    nodeId?: string | null;
    options?:
      | (DrivePage & {
          readonly driveId?: string | null;
          readonly skip?: number;
        })
      | undefined;
  }): AsyncResult<DriveFolderView<F>>;
  /** The caller's role on the node and the flags that role gives. */
  can(id: string): AsyncResult<DriveFlags>;
  /**
   * Adds a file in one call: `upload`, the bytes to storage, then `commit`.
   * When storage refuses the bytes or the commit fails, the pending file is
   * deleted again. Needs `storage` and a client whose storage has `upload`.
   */
  put(input: {
    organizationId: string;
    parentId?: string | null;
    driveId?: string | null;
    /** The file's name; a `File` gives its own. */
    name?: string;
    file: Blob & { readonly name?: string };
    conflict?: DriveConflict;
    fields?: Readonly<Record<string, unknown>>;
  }): AsyncResult<DriveNode<F>>;
  /**
   * Gives every grant on every node, one node at a time. It stops at the first
   * failure; the grants already given stay.
   */
  shareMany(input: {
    ids: readonly string[];
    grants: readonly DriveGrantInput[];
  }): AsyncResult<readonly DriveGrant[]>;
  /**
   * The node's grants with each principal's name. The block stores no member
   * names, so `names` looks them up (profiles, teams or your own table); it
   * runs once per distinct principal.
   */
  grantsWithNames(input: {
    id: string;
    names: DriveNames;
  }): AsyncResult<readonly DriveNamedGrant[]>;
  /**
   * Nodes the caller can read whose name or stored text contains the query,
   * folders first. An empty query returns nothing.
   */
  search(input: {
    organizationId: string;
    query: string;
    pageSize?: number;
  }): AsyncResult<readonly DriveNode<F>[]>;
}

const flagsOf = (value: unknown): DriveFlags => {
  const row = recordOf(value, "drive_node_access");
  const role = row["role"];

  return {
    role: typeof role === "string" ? role : undefined,
    read: row["read"] === true,
    comment: row["comment"] === true,
    download: row["download"] === true,
    upload: row["upload"] === true,
    write: row["write"] === true,
    share: row["share"] === true,
  };
};

const principalKey = (principal: DrivePrincipal): string =>
  `${principal.type}:${principal.id}`;

/** `self` is the finished client, so its hooks and field parsing apply. */
export function driveHelpers(
  call: BlockCall,
  self: () => Drive,
  storage: AttachmentStorage | undefined,
): DriveHelpers {
  return {
    folder: ({ organizationId, nodeId = null, options }) =>
      AsyncResult.from<DriveFolderView>(async () => {
        const drive = self();

        if (nodeId === null) {
          const children = await drive.list({
            organizationId,
            options: { ...options, parentId: null },
          });

          return children.ok
            ? ok({
                node: undefined,
                children: children.data,
                breadcrumbs: [],
                access: undefined,
                grants: [],
              })
            : children;
        }

        const [node, children, breadcrumbs, access, grants] = await Promise.all(
          [
            drive.get(nodeId),
            drive.list({
              organizationId,
              options: { ...options, parentId: nodeId },
            }),
            drive.path(nodeId),
            drive.can(nodeId),
            drive.grants(nodeId),
          ],
        );

        const failed = firstFailure([
          node,
          children,
          breadcrumbs,
          access,
          grants,
        ]);

        if (failed) {
          return failed;
        }

        if (
          !node.ok ||
          !children.ok ||
          !breadcrumbs.ok ||
          !access.ok ||
          !grants.ok
        ) {
          return err(dbError("invalid_request", "The folder read failed"));
        }

        return ok({
          node: node.data,
          children: children.data,
          breadcrumbs: breadcrumbs.data,
          access: access.data,
          grants: grants.data,
        });
      }),
    can: (id) => call("drive_node_access", { node: id }, flagsOf),
    put: ({
      organizationId,
      parentId,
      driveId,
      name,
      file,
      conflict,
      fields,
    }) =>
      AsyncResult.from(async () => {
        const drive = self();
        const fileName = name ?? file.name;

        if (storage === undefined) {
          return err(
            dbError("invalid_request", "createDrive needs storage for files", {
              hint: "DRIVE_STORAGE_CLIENT",
            }),
          );
        }

        if (fileName === undefined || fileName === "") {
          return err(
            dbError("invalid_input", "put needs a name or a File", {
              hint: "DRIVE_NAME_REQUIRED",
            }),
          );
        }

        const pending = await drive.upload({
          organizationId,
          file: {
            name: fileName,
            mimeType: file.type === "" ? "application/octet-stream" : file.type,
            size: file.size,
            ...(parentId !== undefined && { parentId }),
            ...(driveId !== undefined && { driveId }),
            ...(conflict !== undefined && { conflict }),
            ...(fields !== undefined && { fields }),
          },
        });

        if (!pending.ok) {
          return pending;
        }

        const stored = await putRequestFile(
          storage,
          pending.data.attachment,
          file,
        );

        const committed = stored.ok
          ? await drive.commit({
              id: pending.data.node.id,
              attachmentId: pending.data.attachment.id,
            })
          : stored;

        if (committed.ok) {
          return committed;
        }

        // The pending file would otherwise stay in the folder with no content.
        await drive.delete(pending.data.node.id);

        return committed;
      }),
    shareMany: ({ ids, grants }) =>
      AsyncResult.from(async () => {
        const drive = self();
        const given: DriveGrant[] = [];

        for (const id of ids) {
          for (const { principal, role, expiresAt } of grants) {
            const result = await drive.share({
              id,
              principal,
              role,
              ...(expiresAt !== undefined && { expiresAt }),
            });

            if (!result.ok) {
              return result;
            }

            given.push(result.data);
          }
        }

        return ok(given);
      }),
    grantsWithNames: ({ id, names }) =>
      self()
        .grants(id)
        .andThen((grants) =>
          AsyncResult.from(async () => {
            const distinct = new Map(
              grants.map((grant) => [
                principalKey(grant.principal),
                grant.principal,
              ]),
            );

            const resolved = new Map<string, string | undefined>();

            await Promise.all(
              [...distinct].map(async ([key, principal]) => {
                resolved.set(key, await names(principal));
              }),
            );

            return ok(
              grants.map((grant) => ({
                ...grant,
                name: resolved.get(principalKey(grant.principal)),
              })),
            );
          }),
        ),
    search: ({ organizationId, query, pageSize }) =>
      call(
        "drive_search",
        { tenant: organizationId, query, page_size: pageSize ?? 25 },
        (value) => nodesOf(value, "drive_search"),
      ),
  };
}
