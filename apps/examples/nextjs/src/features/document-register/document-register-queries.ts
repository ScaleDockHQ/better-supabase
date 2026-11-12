import "server-only";
import type { DriveRevision } from "better-supabase/blocks/drive";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type { Loaded } from "@/features/people/people-queries";

import { CUSTOMERS_TAG } from "@/features/customers/customers-cache";
import { DRIVE_TAG } from "@/features/drive/drive-cache";
import { driveOf } from "@/features/drive/drive-client";
import { settle } from "@/features/people/people-queries";
import { bsb } from "@/lib/supabase/server";

import type { RegisterRow } from "./document-register-list";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

/** Every controlled document of the organization; the list kit pages them. */
export async function readRegisterRows(
  db: Db,
  organizationId: string,
): Promise<readonly RegisterRow[]> {
  const documents = await driveOf(db).documents({ organizationId }).orThrow();

  return documents.flatMap((node): RegisterRow[] =>
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

async function loadRegister(): Promise<readonly RegisterRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(DRIVE_TAG, CUSTOMERS_TAG);
  const tenant = tenantOf(session);

  return tenant ? readRegisterRows(db, tenant) : null;
}

export function getRegister(): Promise<Loaded<readonly RegisterRow[]>> {
  return settle(loadRegister);
}

export interface RegisterDetailData {
  readonly row: RegisterRow;
  readonly reviewIntervalMonths: number | null;
  readonly effectiveFrom: string | null;
  readonly revisions: readonly {
    readonly id: string;
    readonly number: number;
    readonly label: string | null;
    readonly current: boolean;
    readonly createdAt: string;
  }[];
}

async function loadDocument(
  id: string,
): Promise<RegisterDetailData | "not-found" | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(DRIVE_TAG, CUSTOMERS_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const drive = driveOf(db);
  const documents = await drive.documents({ organizationId: tenant }).orThrow();
  const node = documents.find((entry) => entry.id === id);

  if (node?.document === undefined) {
    return "not-found";
  }

  const revisions: readonly DriveRevision[] = await drive
    .revisions(id)
    .orThrow();

  return {
    row: {
      id: node.id,
      number: node.document.number,
      name: node.name,
      type: node.document.type,
      status: node.document.status,
      effectiveVersion: node.document.effectiveVersion ?? null,
      nextReviewOn: node.document.nextReviewOn?.toString() ?? null,
      reviewDue: node.document.reviewDue,
    },
    reviewIntervalMonths: node.document.reviewIntervalMonths ?? null,
    effectiveFrom: node.document.effectiveFrom?.toString() ?? null,
    revisions: revisions.map((revision) => ({
      id: revision.id,
      number: revision.number,
      label: revision.label ?? null,
      current: revision.current,
      createdAt: revision.createdAt.toString(),
    })),
  };
}

export function getRegisterDocument(
  id: string,
): Promise<Loaded<RegisterDetailData | "not-found">> {
  return settle(() => loadDocument(id));
}
