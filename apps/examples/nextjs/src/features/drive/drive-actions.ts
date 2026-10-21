"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { bs } from "@/lib/supabase/server";

import { driveOf } from "./drive-client";

const Id = v.pipe(v.string(), v.uuid());
const Name = v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(255));

/** A hidden form field: empty for the root folder. */
const ParentId = v.pipe(
  v.optional(v.union([v.literal(""), Id]), ""),
  v.transform((id) => (id === "" ? null : id)),
);

export const createDriveFolder = bs.action(
  {
    input: v.object({ parentId: ParentId, name: Name }),
    requireTenant: true,
    authorize: (session) => can(session, "drive.create"),
  },
  async ({ parentId, name }, { tenant, supabase, auth }) => {
    const folder = await driveOf(supabase).createFolder(tenant, {
      parentId,
      name,
      conflict: "rename",
    });

    if (!folder.ok) {
      return folder;
    }

    refreshCaller(auth);

    return ok({ id: folder.data.id, name: folder.data.name });
  },
);

/**
 * Creates the file node and a signed upload URL. The browser sends the bytes
 * straight to Storage, so the file never passes the Server Action body limit,
 * then calls `commitDriveUpload`.
 */
export const startDriveUpload = bs.action(
  {
    input: v.object({
      parentId: v.nullable(Id),
      name: Name,
      mimeType: v.pipe(v.string(), v.maxLength(255)),
      size: v.pipe(v.number(), v.integer(), v.minValue(1)),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "drive.create"),
  },
  async ({ parentId, name, mimeType, size }, { tenant, supabase }) => {
    const upload = await driveOf(supabase).upload(tenant, {
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
export const commitDriveUpload = bs.action(
  {
    input: v.object({ nodeId: Id, attachmentId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "drive.create"),
  },
  async ({ nodeId, attachmentId }, { supabase, auth }) => {
    const committed = await driveOf(supabase).commit(nodeId, attachmentId);

    if (!committed.ok) {
      return committed;
    }

    refreshCaller(auth);

    return ok({ id: committed.data.id, name: committed.data.name });
  },
);

/** Removes a file whose bytes never reached Storage. */
export const abandonDriveUpload = bs.action(
  {
    input: v.object({ nodeId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "drive.create"),
  },
  async ({ nodeId }, { supabase }) => driveOf(supabase).delete(nodeId),
);

export const renameDriveItem = bs.action(
  {
    input: v.object({ id: Id, name: Name }),
    requireTenant: true,
    authorize: (session) => can(session, "drive.create"),
  },
  async ({ id, name }, { supabase, auth }) => {
    const renamed = await driveOf(supabase).rename(id, name, {
      conflict: "rename",
    });

    if (!renamed.ok) {
      return renamed;
    }

    refreshCaller(auth);

    return ok({ id: renamed.data.id, name: renamed.data.name });
  },
);

/**
 * Moves the item and everything under it to the trash; returns the trash item
 * for Undo.
 */
export const trashDriveItem = bs.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "drive.create"),
  },
  async ({ id }, { supabase, auth }) => {
    const trashed = await driveOf(supabase).trash(id);

    if (!trashed.ok) {
      return trashed;
    }

    refreshCaller(auth);

    return ok({ trashItemId: trashed.data.id, count: trashed.data.count });
  },
);

/** A short-lived signed URL for the file's current content. */
export const downloadDriveFile = bs.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "drive.read"),
  },
  async ({ id }, { supabase }) => {
    const download = await driveOf(supabase).download(id, { as: true });

    if (!download.ok) {
      return download;
    }

    return ok({ url: download.data.signedUrl });
  },
);
