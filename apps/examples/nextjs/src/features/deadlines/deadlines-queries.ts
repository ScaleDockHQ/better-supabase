import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type { Loaded } from "@/features/people/people-queries";

import { settle } from "@/features/people/people-queries";
import { bsb } from "@/lib/supabase/server";

import type { DeadlineRow } from "./deadlines-list";

import { DEADLINES_TAG } from "./deadlines-cache";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

/**
 * The deadlines the caller reads. The block lists up to 500 and has no search,
 * so the list kit searches, filters and pages them on the server (EX-901).
 */
export async function readDeadlineRows(
  db: Db,
): Promise<readonly DeadlineRow[]> {
  const deadlines = await db.deadlines.list({ limit: 500 }).orThrow();

  return deadlines.map((deadline): DeadlineRow => ({
    id: deadline.id,
    subjectType: deadline.subjectType,
    subjectId: deadline.subjectId,
    kind: deadline.kind,
    jurisdiction: deadline.jurisdiction,
    groupKey: deadline.groupKey,
    result: deadline.result,
    dueOn: deadline.dueOn?.toString() ?? null,
    provisional: deadline.provisional,
    state: deadline.state,
    missing: deadline.missing.length,
    computedAt: deadline.computedAt.toString(),
  }));
}

async function loadDeadlines(): Promise<readonly DeadlineRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(DEADLINES_TAG);

  return tenantOf(session) ? readDeadlineRows(db) : null;
}

export function getDeadlines(): Promise<Loaded<readonly DeadlineRow[]>> {
  return settle(loadDeadlines);
}
