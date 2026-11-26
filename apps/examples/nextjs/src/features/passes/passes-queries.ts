import "server-only";
import type { Result } from "better-supabase";

import { ok } from "better-supabase";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type { BlockPage } from "@/lib/block-page";
import type { BlockListQuery } from "@/lib/block-status-list";

import { encodeCursor, pageOptionsOf } from "@/lib/block-page";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

import type { PassRow } from "./pass-row";

import { PASS_PAGE_SIZE, PASS_STATUSES, passList } from "./passes-list";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

const isStatus = (value: string): value is PassRow["status"] =>
  PASS_STATUSES.some((status) => status === value);

/** One page of passes, shared by the page and `/api/passes/list`. */
export async function getPassPage(
  db: Db,
  query: BlockListQuery<"newest">,
): Promise<Result<BlockPage<PassRow>>> {
  const statuses = (query.facets["status"] ?? []).filter(isStatus);

  const result = await db.passes.passPage(
    pageOptionsOf(query, PASS_PAGE_SIZE, { status: statuses }),
  );

  if (!result.ok) {
    return result;
  }

  return ok({
    items: result.data.items.map((pass): PassRow => ({
      id: pass.id,
      kind: pass.kind,
      holder: pass.holderName ?? pass.holderEmail ?? null,
      status: pass.status,
      uses: pass.uses,
      usesAllowed: pass.usesAllowed ?? null,
      validFrom: pass.validFrom.toString(),
      validUntil: pass.validUntil?.toString() ?? null,
      createdAt: pass.createdAt.toString(),
    })),
    nextCursor: encodeCursor(result.data.nextCursor),
  });
}

/** The first page of passes, for the instant shell. */
export async function getPasses(): Promise<BlockPage<PassRow> | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.passes());

  if (!tenantOf(session)) {
    return null;
  }

  const result = await getPassPage(db, passList.defaults);

  if (!result.ok) {
    throw new Error(result.error.message);
  }

  return result.data;
}

/** One pass; `null` when RLS hides it. */
export async function getPass(id: string): Promise<PassRow | null> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(tags.passes());

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
  cacheTag(tags.passes());

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
