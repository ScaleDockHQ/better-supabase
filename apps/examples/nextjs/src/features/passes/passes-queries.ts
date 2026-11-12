import "server-only";
import type { Result } from "better-supabase";
import type { PassListOptions } from "better-supabase/blocks/passes";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { Temporal } from "temporal-polyfill";

import type { BlockPage } from "@/lib/block-page";
import type { BlockListQuery, Mutable } from "@/lib/block-status-list";

import { pageOverStatuses } from "@/lib/block-page";
import { bsb } from "@/lib/supabase/server";

import type { PassRow } from "./pass-row";

import { PASSES_TAG } from "./passes-cache";
import { PASS_PAGE_SIZE, PASS_STATUSES, passList } from "./passes-list";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

const isStatus = (value: string): value is PassRow["status"] =>
  PASS_STATUSES.some((status) => status === value);

/** One page of passes, shared by the page and `/api/passes/list`. */
export function loadPassPage(
  db: Db,
  query: BlockListQuery<"newest">,
): Promise<Result<BlockPage<PassRow>>> {
  const before =
    query.after === undefined ? undefined : Temporal.Instant.from(query.after);

  return pageOverStatuses({
    statuses: query.facets["status"],
    size: PASS_PAGE_SIZE,
    fetchPage: (status, take) => {
      const options: Mutable<PassListOptions> = { pageSize: take };

      if (status !== undefined && isStatus(status)) {
        options.status = status;
      }

      if (before !== undefined) {
        options.before = before;
      }

      return db.passes.list(options);
    },
    map: (pass): PassRow => ({
      id: pass.id,
      kind: pass.kind,
      holder: pass.holderName ?? pass.holderEmail ?? null,
      status: pass.status,
      uses: pass.uses,
      usesAllowed: pass.usesAllowed ?? null,
      validFrom: pass.validFrom.toString(),
      validUntil: pass.validUntil?.toString() ?? null,
      createdAt: pass.createdAt.toString(),
    }),
  });
}

/** The first page of passes, for the instant shell. */
export async function getPasses(): Promise<BlockPage<PassRow> | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(PASSES_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const result = await loadPassPage(db, passList.defaults);

  if (!result.ok) {
    throw new Error(result.error.message);
  }

  return result.data;
}

/** One pass; `null` when RLS hides it. */
export async function getPass(id: string): Promise<PassRow | null> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(PASSES_TAG);

  const result = await db.passes.get(id);

  if (!result.ok) {
    throw new Error(result.error.message);
  }

  const pass = result.data;

  return pass === null
    ? null
    : {
        id: pass.id,
        kind: pass.kind,
        holder: pass.holderName ?? pass.holderEmail ?? null,
        status: pass.status,
        uses: pass.uses,
        usesAllowed: pass.usesAllowed ?? null,
        validFrom: pass.validFrom.toString(),
        validUntil: pass.validUntil?.toString() ?? null,
        createdAt: pass.createdAt.toString(),
      };
}

export interface PassCheckInRow {
  readonly id: string;
  readonly method: string;
  readonly gate: string | null;
  readonly admitted: boolean;
  readonly reason: string | null;
  readonly createdAt: string;
}

/** The pass's scans, newest first. */
export async function getPassCheckIns(
  id: string,
): Promise<readonly PassCheckInRow[]> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(PASSES_TAG);

  const result = await db.passes.checkIns({ passId: id, pageSize: 25 });

  if (!result.ok) {
    throw new Error(result.error.message);
  }

  return result.data.map((scan) => ({
    id: scan.id,
    method: scan.method,
    gate: scan.gate ?? null,
    admitted: scan.admitted,
    reason: scan.reason ?? null,
    createdAt: scan.createdAt.toString(),
  }));
}
