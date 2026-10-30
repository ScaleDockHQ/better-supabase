import "server-only";
import type { ApprovalStatus } from "better-supabase/blocks/approvals";
import type { DriveDocumentStatus } from "better-supabase/blocks/drive";

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
  /** Someone has the file checked out. */
  readonly locked: boolean;
  readonly downloadBlocked: boolean;
  /** Whether the caller may download the original. */
  readonly downloadable: boolean;
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
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const drive = driveOf(db);

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
      locked: node.lockedBy !== undefined,
      downloadBlocked: node.downloadBlocked,
      downloadable: node.downloadable !== false,
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

/** A controlled document as the register shows it, serializable. */
export interface DocumentRow {
  readonly id: string;
  readonly number: string;
  readonly name: string;
  readonly type: string;
  readonly status: DriveDocumentStatus;
  /** The released revision, or null before the first release. */
  readonly effectiveVersion: number | null;
  /** ISO 8601 date. */
  readonly nextReviewOn: string | null;
  readonly reviewDue: boolean;
}

export type DocumentRegisterView =
  | { readonly kind: "ok"; readonly documents: readonly DocumentRow[] }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

async function loadRegister(): Promise<readonly DocumentRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const documents = await driveOf(db).documents(tenant);

  if (!documents.ok) {
    throw new Error(documents.error.message);
  }

  return documents.data.flatMap((node): DocumentRow[] =>
    node.document === undefined
      ? []
      : [
          {
            id: node.id,
            number: node.document.number,
            name: node.name,
            type: node.document.type,
            status: node.document.status,
            effectiveVersion: node.document.effectiveVersion ?? null,
            nextReviewOn: node.document.nextReviewOn?.toString() ?? null,
            reviewDue: node.document.reviewDue,
          },
        ],
  );
}

/** The organization's controlled documents, by number. */
export async function getDocumentRegister(): Promise<DocumentRegisterView> {
  try {
    const documents = await loadRegister();

    return documents === null
      ? { kind: "no-organization" }
      : { kind: "ok", documents };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}
