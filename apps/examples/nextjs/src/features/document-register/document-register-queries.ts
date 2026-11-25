import "server-only";
import type { DriveNode, DriveRevision } from "better-supabase/blocks/drive";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type {
  RecordListPage,
  RecordListUrlQuery,
} from "@/components/record-list/record-list-types";
import type { Loaded } from "@/features/people/people-queries";

import { CUSTOMERS_TAG } from "@/features/customers/customers-cache";
import { DRIVE_TAG } from "@/features/drive/drive-cache";
import { driveOf } from "@/features/drive/drive-client";
import { settle } from "@/features/people/people-queries";
import { pageEntityRows } from "@/lib/block-entity-page";
import { bsb } from "@/lib/supabase/server";

import type { RegisterRow } from "./document-register-list";

import { registerList, registerMap } from "./document-register-list";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

const rowOf = (node: DriveNode): RegisterRow[] =>
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
      ];

/**
 * One page of controlled documents for a list query, searched, filtered and
 * sorted by the drive block's `documentPage` and counted by `documentFacets`.
 */
export function getRegisterPage(
  db: Db,
  organizationId: string,
  query: RecordListUrlQuery,
): Promise<RecordListPage<RegisterRow>> {
  const drive = driveOf(db);

  return pageEntityRows({
    pager: {
      page: (options) => drive.documentPage({ organizationId, ...options }),
      facets: (options) => drive.documentFacets({ organizationId, ...options }),
    },
    map: registerMap,
    query,
    pageSize: registerList.config.pageSize,
    rowsOf: (nodes) => nodes.flatMap(rowOf),
  });
}

async function loadRegister(): Promise<RecordListPage<RegisterRow> | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(DRIVE_TAG, CUSTOMERS_TAG);
  const tenant = tenantOf(session);

  return tenant ? getRegisterPage(db, tenant, registerList.defaults) : null;
}

export function getRegister(): Promise<Loaded<RecordListPage<RegisterRow>>> {
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
  const found = await drive.getDocument(id);

  if (!found.ok && found.error.kind !== "not_found") {
    throw new Error(found.error.message);
  }

  const node = found.ok ? found.data : null;

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
