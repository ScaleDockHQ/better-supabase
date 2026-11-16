import type { EntityListReads } from "better-supabase/list";

import type { AppDb, EntityListMap } from "@/lib/block-entity-page";

import { blockEntityReads, organizationPager } from "@/lib/block-entity-page";

import type { SegmentRow } from "../automation/automation-queries";

/** The segments list's sorts on the segments block's. */
const segmentSorts: EntityListMap["sorts"] = {
  name: { by: "name" },
  members: { by: "memberCount", direction: "desc" },
};

/** The segments list's URL names on the segments block's page. */
export const segmentsMap: EntityListMap = {
  sorts: segmentSorts,
  filters: { f: "subjectType" },
  facets: { f: "subjectType" },
};

/** The segment as the list shows it. */
export function segmentOf(segment: {
  readonly id: string;
  readonly name: string;
  readonly description: string | undefined;
  readonly subjectType: string;
  readonly memberCount: number;
  readonly refreshedAt: { toString(): string } | undefined;
  readonly conditions: { readonly rules: readonly unknown[] };
}): SegmentRow {
  return {
    id: segment.id,
    name: segment.name,
    description: segment.description ?? null,
    subjectType: segment.subjectType,
    memberCount: segment.memberCount,
    refreshedAt: segment.refreshedAt?.toString() ?? null,
    rules: segment.conditions.rules.length,
  };
}

/** The segments block's `page` and `facets` for an organization. */
export function segmentsPager(db: AppDb, organizationId: string) {
  return organizationPager(organizationId, {
    page: (options) => db.segments.page(options),
    facets: (options) => db.segments.facets(options),
  });
}

/** The reads module of the `app.segments` entity page (ADR 0894). */
export function segmentsReads(db: AppDb): EntityListReads<SegmentRow> {
  return blockEntityReads({
    pager: (organizationId) => segmentsPager(db, organizationId),
    map: { sorts: segmentSorts },
    wire: segmentOf,
  });
}
