import type { EntityListReads } from "better-supabase/list";

import type { BlockListSpec } from "@/lib/array-list";
import type { AppDb } from "@/lib/array-reads";

import { arrayReads } from "@/lib/array-reads";

import type { QueueRow } from "../automation/automation-queries";

/**
 * The search, sort and facet of the assignment queues list, shared with its
 * overview.
 */
export const queuesSpec: BlockListSpec<QueueRow> = {
  search: (queue) => queue.name,
  facet: (queue) => queue.strategy,
  defaultSort: "rank",
  sorts: {
    rank: (a, b) => a.rank - b.rank,
    name: (a, b) => a.name.localeCompare(b.name),
    assigned: (a, b) => b.assigned - a.assigned,
  },
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

/** The assignment queues of the organization. */
export function queuesFrom(db: AppDb, tenant: string) {
  return db.assignment
    .queues({ organizationId: tenant })
    .map((queues) => queues.map(queueOf));
}

/** The reads module of the `app.queues` entity page (ADR 0894). */
export function queuesReads(db: AppDb): EntityListReads<QueueRow> {
  return arrayReads({
    load: (tenant) => queuesFrom(db, tenant),
    facet: "strategy",
    spec: queuesSpec,
    wire: (queue) => queue,
  });
}
