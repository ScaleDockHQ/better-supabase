import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type {
  RecordListPage,
  RecordListUrlQuery,
} from "@/components/record-list/record-list-types";
import type { Loaded } from "@/features/people/people-queries";

import { settle } from "@/features/people/people-queries";
import { pageEntityRows } from "@/lib/block-entity-page";
import { bsb } from "@/lib/supabase/server";

import type { DeadlineRow } from "./deadlines-list";

import { DEADLINES_TAG } from "./deadlines-cache";
import { deadlineList, deadlineMap } from "./deadlines-list";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

/**
 * One page of the deadlines the caller reads, searched, filtered and sorted by
 * the deadlines block's `page` and counted by its `facets`.
 */
export function loadDeadlinePage(
  db: Db,
  query: RecordListUrlQuery,
): Promise<RecordListPage<DeadlineRow>> {
  const { deadlines } = db;

  return pageEntityRows({
    pager: {
      page: (options) => deadlines.page(options),
      facets: (options) => deadlines.facets(options),
    },
    map: deadlineMap,
    query,
    pageSize: deadlineList.config.pageSize,
    rowsOf: (items) =>
      items.map((deadline): DeadlineRow => ({
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
      })),
  });
}

async function loadDeadlines(): Promise<RecordListPage<DeadlineRow> | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(DEADLINES_TAG);

  return tenantOf(session) ? loadDeadlinePage(db, deadlineList.defaults) : null;
}

export function getDeadlines(): Promise<Loaded<RecordListPage<DeadlineRow>>> {
  return settle(loadDeadlines);
}
