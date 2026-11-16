import type { EntityListReads } from "better-supabase/list";

import type { AppDb, EntityListMap } from "@/lib/block-entity-page";
import type { LoadedSpec } from "@/lib/loaded-pager";

import { blockEntityReads } from "@/lib/block-entity-page";
import { loadedPager } from "@/lib/loaded-pager";

import type { QueueRow } from "../automation/automation-queries";

/**
 * How the assignment queues are searched, filtered and sorted. The `assignment`
 * block returns its queues whole (`queues`), so this is the one list that stays
 * a thin per-page read.
 */
const queuesSpec: LoadedSpec<QueueRow> = {
  search: (queue) => queue.name,
  facets: { strategy: (queue) => queue.strategy },
  sorts: {
    rank: (a, b) => a.rank - b.rank,
    name: (a, b) => a.name.localeCompare(b.name),
    assigned: (a, b) => a.assigned - b.assigned,
  },
};

/** The queues list's sorts on the spec's. */
const queueSorts: EntityListMap["sorts"] = {
  rank: { by: "rank" },
  name: { by: "name" },
  assigned: { by: "assigned", direction: "desc" },
};

/** The queues overview's URL names on the spec's. */
export const queuesMap: EntityListMap = {
  sorts: queueSorts,
  filters: { f: "strategy" },
  facets: { f: "strategy" },
};

/** The queue as the list shows it. */
export function queueOf(queue: {
  readonly id: string;
  readonly name: string;
  readonly subjectType: string;
  readonly strategy: string;
  readonly rank: number;
  readonly enabled: boolean;
  readonly members: readonly { readonly assignedCount: number }[];
}): QueueRow {
  return {
    id: queue.id,
    name: queue.name,
    subjectType: queue.subjectType,
    strategy: queue.strategy,
    rank: queue.rank,
    enabled: queue.enabled,
    members: queue.members.length,
    assigned: queue.members.reduce(
      (sum, member) => sum + member.assignedCount,
      0,
    ),
  };
}

/** The assignment queues of the organization, searched and paged in memory. */
export function queuesPager(db: AppDb, tenant: string) {
  return loadedPager(
    () =>
      db.assignment
        .queues({ organizationId: tenant })
        .map((queues) => queues.map(queueOf)),
    queuesSpec,
  );
}

/** The reads module of the `app.queues` entity page (ADR 0894). */
export function queuesReads(db: AppDb): EntityListReads<QueueRow> {
  return blockEntityReads({
    pager: (tenant) => queuesPager(db, tenant),
    map: { sorts: queueSorts },
    wire: (queue) => queue,
  });
}
