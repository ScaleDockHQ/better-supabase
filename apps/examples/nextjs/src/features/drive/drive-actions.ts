"use server";

import { ok, dbError, err } from "better-supabase";
import { createDrive, rpcTransport } from "better-supabase/blocks/drive";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { CUSTOMERS_TAG } from "@/features/customers/customers-cache";
import { getMembers } from "@/features/organization/organization-queries";
import { refreshCaller } from "@/lib/refresh-caller";
import { blockConfig } from "@/lib/supabase/blocks.config";
import { bsb } from "@/lib/supabase/server";

import { DRIVE_TAG } from "./drive-cache";
import { driveOf } from "./drive-client";
import { DRIVE_ROLES } from "./drive-roles";

const Id = v.pipe(v.string(), v.uuid());
const Name = v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(255));

/** A hidden form field: empty for the root folder. */
const ParentId = v.pipe(
  v.optional(v.union([v.literal(""), Id]), ""),
  v.transform((id) => (id === "" ? null : id)),
);

export const createDriveFolder = bsb.action(
  {
    input: v.object({ parentId: ParentId, name: Name }),
    requireTenant: true,
    permission: "drive.create",
  },
  async ({ parentId, name }, { tenant, db, auth }) => {
    const folder = await driveOf(db).createFolder({
      organizationId: tenant,
      folder: { parentId, name, conflict: "rename" },
    });

    if (!folder.ok) {
      return folder;
    }

    await refreshCaller(auth, [DRIVE_TAG, CUSTOMERS_TAG]);

    return ok({ id: folder.data.id, name: folder.data.name });
  },
);

/**
 * Creates the file node and a signed upload URL. The browser sends the bytes
 * straight to Storage, so the file never passes the Server Action body limit,
 * then calls `commitDriveUpload`.
 */
export const startDriveUpload = bsb.action(
  {
    input: v.object({
      parentId: v.nullable(Id),
      name: Name,
      mimeType: v.pipe(v.string(), v.maxLength(255)),
      size: v.pipe(v.number(), v.integer(), v.minValue(1)),
    }),
    requireTenant: true,
    permission: "drive.create",
  },
  async ({ parentId, name, mimeType, size }, { tenant, db }) => {
    const upload = await driveOf(db).upload({
      organizationId: tenant,
      file: {
        parentId,
        name,
        mimeType: mimeType || "application/octet-stream",
        size,
        conflict: "rename",
      },
    });

    if (!upload.ok) {
      return upload;
    }

    const { node, attachment, token } = upload.data;

    return ok({
      nodeId: node.id,
      attachmentId: attachment.id,
      bucket: attachment.bucket,
      path: attachment.path,
      token,
    });
  },
);

/** Makes the uploaded object the file's content. */
export const commitDriveUpload = bsb.action(
  {
    input: v.object({ nodeId: Id, attachmentId: Id }),
    requireTenant: true,
    permission: "drive.create",
  },
  async ({ nodeId, attachmentId }, { db, auth }) => {
    const committed = await driveOf(db).commit({ id: nodeId, attachmentId });

    if (!committed.ok) {
      return committed;
    }

    await refreshCaller(auth, [DRIVE_TAG, CUSTOMERS_TAG]);

    return ok({ id: committed.data.id, name: committed.data.name });
  },
);

/** Removes a file whose bytes never reached Storage. */
export const abandonDriveUpload = bsb.action(
  {
    input: v.object({ nodeId: Id }),
    requireTenant: true,
    permission: "drive.create",
  },
  async ({ nodeId }, { db }) => driveOf(db).delete(nodeId),
);

export const renameDriveItem = bsb.action(
  {
    input: v.object({ id: Id, name: Name }),
    requireTenant: true,
    permission: "drive.create",
  },
  async ({ id, name }, { db, auth }) => {
    const renamed = await driveOf(db).rename({ id, name, conflict: "rename" });

    if (!renamed.ok) {
      return renamed;
    }

    await refreshCaller(auth, [DRIVE_TAG, CUSTOMERS_TAG]);

    return ok({ id: renamed.data.id, name: renamed.data.name });
  },
);

/**
 * Moves the item and everything under it to the trash; returns the trash item
 * for Undo.
 */
export const trashDriveItem = bsb.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    permission: "drive.create",
  },
  async ({ id }, { db, auth }) => {
    const trashed = await driveOf(db).trash(id);

    if (!trashed.ok) {
      return trashed;
    }

    await refreshCaller(auth, [DRIVE_TAG, CUSTOMERS_TAG]);

    return ok({ trashItemId: trashed.data.id, count: trashed.data.count });
  },
);

/** A short-lived signed URL for the file's current content. */
export const downloadDriveFile = bsb.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    permission: "drive.read",
  },
  async ({ id }, { db }) => {
    const download = await driveOf(db).download({ id, options: { as: true } });

    if (!download.ok) {
      return download;
    }

    return ok({ url: download.data.signedUrl });
  },
);

/** Checks the file out for two hours, or checks it back in. */
export const setDriveCheckout = bsb.action(
  {
    input: v.object({ id: Id, locked: v.boolean() }),
    requireTenant: true,
    permission: "drive.create",
  },
  async ({ id, locked }, { db, auth }) => {
    const drive = driveOf(db);

    const node = locked
      ? await drive.lock({
          id,
          until: Temporal.Now.instant().add({ hours: 2 }),
        })
      : await drive.unlock({ id });

    if (!node.ok) {
      return node;
    }

    await refreshCaller(auth, [DRIVE_TAG, CUSTOMERS_TAG]);

    return ok({ id: node.data.id, locked: node.data.lockedBy !== undefined });
  },
);

/** Keeps the original from viewers; they still see the previews. */
export const setDriveDownloadsBlocked = bsb.action(
  {
    input: v.object({ id: Id, blocked: v.boolean() }),
    requireTenant: true,
    permission: "drive.create",
  },
  async ({ id, blocked }, { db, auth }) => {
    const node = await driveOf(db).blockDownloads({ id, blocked });

    if (!node.ok) {
      return node;
    }

    await refreshCaller(auth, [DRIVE_TAG, CUSTOMERS_TAG]);

    return ok({ id: node.data.id, blocked: node.data.downloadBlocked });
  },
);

/** Asks for approval of the file's current version. */
export const requestDriveApproval = bsb.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    permission: "drive.create",
  },
  async ({ id }, { db, auth }) => {
    const requested = await driveOf(db).requestApproval({ id });

    if (!requested.ok) {
      return requested;
    }

    await refreshCaller(auth, [DRIVE_TAG, CUSTOMERS_TAG]);

    return ok({ id: requested.data.id, revision: requested.data.revision });
  },
);

const Principal = v.object({ type: v.picklist(["user", "team"]), id: Id });

export interface SharingGrant {
  readonly type: "user" | "team" | "role";
  readonly id: string;
  readonly name: string;
  readonly role: string;
  /** Granted on a folder above the item, so it is removed there. */
  readonly inherited: boolean;
}

export interface SharingTarget {
  readonly type: "user" | "team";
  readonly id: string;
  readonly name: string;
}

/**
 * The item's grants, inherited ones included, and the members and teams it can
 * be shared with. The drive functions decide who may read the grants.
 */
export const loadDriveSharing = bsb.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    permission: "drive.read",
  },
  async ({ id }, { tenant, db }) => {
    const [grants, members, teams] = await Promise.all([
      driveOf(db).grants(id),
      getMembers(tenant),
      db.teams.list(tenant),
    ]);

    if (!grants.ok) {
      return grants;
    }

    if (!teams.ok) {
      return teams;
    }

    const targets: SharingTarget[] = [
      ...members.map((member) => ({
        type: "user" as const,
        id: member.userId,
        name: member.name ?? member.email ?? member.userId,
      })),
      ...teams.data.map((team) => ({
        type: "team" as const,
        id: team.id,
        name: team.name,
      })),
    ];

    const names = new Map(
      targets.map((target) => [`${target.type}:${target.id}`, target.name]),
    );

    return ok({
      grants: grants.data.map((grant): SharingGrant => ({
        type: grant.principal.type,
        id: grant.principal.id,
        name:
          names.get(`${grant.principal.type}:${grant.principal.id}`) ??
          grant.principal.id,
        role: grant.role,
        inherited: grant.inherited,
      })),
      targets,
    });
  },
);

/** Shares the item with a member or a team; a second share changes the role. */
export const shareDriveItem = bsb.action(
  {
    input: v.object({
      id: Id,
      principal: Principal,
      role: v.picklist(DRIVE_ROLES),
    }),
    requireTenant: true,
    permission: "drive.read",
  },
  async ({ id, principal, role }, { db, auth }) => {
    const shared = await driveOf(db).share({ id, principal, role });

    if (!shared.ok) {
      return shared;
    }

    await refreshCaller(auth, [DRIVE_TAG, CUSTOMERS_TAG]);

    return ok(null);
  },
);

/** Removes a grant made on the item itself. */
export const unshareDriveItem = bsb.action(
  {
    input: v.object({ id: Id, principal: Principal }),
    requireTenant: true,
    permission: "drive.read",
  },
  async ({ id, principal }, { db, auth }) => {
    const removed = await driveOf(db).unshare({ id, principal });

    if (!removed.ok) {
      return removed;
    }

    if (!removed.data) {
      return err(dbError("not_found", "Grant not found"));
    }

    await refreshCaller(auth, [DRIVE_TAG, CUSTOMERS_TAG]);

    return ok(null);
  },
);

/** Next.js caps a Server Action body at 1 MB (`serverActions.bodySizeLimit`). */
const MAX_BYTES = 1_000_000;

/**
 * Sends one file through a file request link, signed in or not. The drive
 * function checks the token, its password, its uses and its rate limit, so the
 * service role here only uploads the bytes to the path it returns.
 */
export const sendToFileRequest = bsb.action(
  {
    input: v.object({
      token: v.pipe(v.string(), v.regex(/^[0-9a-f]{32,128}$/)),
      file: v.pipe(v.file(), v.minSize(1), v.maxSize(MAX_BYTES)),
      password: v.optional(v.pipe(v.string(), v.maxLength(200))),
    }),
    allow: ["none", "user"],
  },
  async ({ token, file, password }) => {
    const service = bsb.admin().$client;

    const drive = createDrive({
      transport: rpcTransport(service, { schema: blockConfig.drive.api }),
      storage: service.storage,
      schema: blockConfig.drive.api,
    });

    const sent = await (password
      ? drive.uploadToRequest({
          token,
          file,
          options: { name: file.name, password },
        })
      : drive.uploadToRequest({ token, file, options: { name: file.name } }));

    if (!sent.ok) {
      return sent;
    }

    return ok(
      sent.data.passwordRequired
        ? { passwordRequired: true as const }
        : { passwordRequired: false as const, name: file.name },
    );
  },
);
