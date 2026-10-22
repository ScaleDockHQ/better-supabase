import "server-only";
import type { ApprovalStatus } from "better-supabase/blocks/approvals";

import { tenantOf } from "better-supabase/next";
import { notFound, unstable_rethrow } from "next/navigation";

import { bsb } from "@/lib/supabase/server";

import { driveOf } from "./drive-client";

const UUID = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

export interface DriveItem {
  readonly id: string;
  readonly kind: "folder" | "file";
  readonly name: string;
  readonly mimeType: string | null;
  readonly size: number | null;
  /** ISO 8601, so the cached value stays serializable. */
  readonly createdAt: string;
  readonly labels: readonly { readonly id: string; readonly name: string }[];
  /** The approval of the file's current version, if one was requested. */
  readonly approval: ApprovalStatus | null;
}

export interface DriveCrumbItem {
  readonly id: string;
  readonly name: string;
}

export type DriveFolderView =
  | {
      readonly kind: "ok";
      readonly folderId: string | null;
      readonly crumbs: readonly DriveCrumbItem[];
      readonly items: readonly DriveItem[];
    }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/**
 * A folder's children (the root for `null`) and the folders above it. A failed
 * read throws, so it is never cached and Retry reads again.
 */
async function loadFolder(folderId: string | null) {
  "use cache: private";
  const { session, supabase } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const drive = driveOf(supabase);

  const [children, path] = await Promise.all([
    drive.list(tenant, { parentId: folderId }),
    folderId === null ? null : drive.path(folderId),
  ]);

  if (path !== null && !path.ok) {
    if (path.error.kind === "not_found") {
      return "not-found" as const;
    }

    throw new Error(path.error.message);
  }

  if (!children.ok) {
    throw new Error(children.error.message);
  }

  return {
    crumbs: (path?.data ?? [])
      .filter((crumb) => crumb.kind === "folder")
      .map((crumb) => ({ id: crumb.id, name: crumb.name })),
    items: children.data.map((node): DriveItem => ({
      id: node.id,
      kind: node.kind,
      name: node.name,
      mimeType: node.file?.mimeType ?? null,
      size: node.file?.size ?? null,
      createdAt: node.createdAt.toString(),
      labels: (node.labels ?? []).map(({ id, name }) => ({ id, name })),
      approval: node.approval?.status ?? null,
    })),
  };
}

export async function getDriveFolder(
  folderId: string | null,
): Promise<DriveFolderView> {
  if (folderId !== null && !UUID.test(folderId)) {
    notFound();
  }

  let folder: Awaited<ReturnType<typeof loadFolder>>;

  try {
    folder = await loadFolder(folderId);
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }

  if (folder === "not-found") {
    notFound();
  }

  return folder === null
    ? { kind: "no-organization" }
    : { kind: "ok", folderId, ...folder };
}
