"use server";

import { ok } from "better-supabase";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { driveOf } from "./drive-client";

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
    const folder = await driveOf(db).createFolder(tenant, {
      parentId,
      name,
      conflict: "rename",
    });

    if (!folder.ok) {
      return folder;
    }

    await refreshCaller(auth);

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
    const upload = await driveOf(db).upload(tenant, {
      parentId,
      name,
      mimeType: mimeType || "application/octet-stream",
      size,
      conflict: "rename",
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
    const committed = await driveOf(db).commit(nodeId, attachmentId);

    if (!committed.ok) {
      return committed;
    }

    await refreshCaller(auth);

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
    const renamed = await driveOf(db).rename(id, name, { conflict: "rename" });

    if (!renamed.ok) {
      return renamed;
    }

    await refreshCaller(auth);

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

    await refreshCaller(auth);

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
    const download = await driveOf(db).download(id, { as: true });

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
      ? await drive.lock(id, {
          until: Temporal.Now.instant().add({ hours: 2 }),
        })
      : await drive.unlock(id);

    if (!node.ok) {
      return node;
    }

    await refreshCaller(auth);

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
    const node = await driveOf(db).blockDownloads(id, blocked);

    if (!node.ok) {
      return node;
    }

    await refreshCaller(auth);

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
    const requested = await driveOf(db).requestApproval(id);

    if (!requested.ok) {
      return requested;
    }

    await refreshCaller(auth);

    return ok({ id: requested.data.id, revision: requested.data.revision });
  },
);
