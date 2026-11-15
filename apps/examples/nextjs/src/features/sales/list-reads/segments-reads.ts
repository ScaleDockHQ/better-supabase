import type { EntityListReads } from "better-supabase/list";

import type { BlockListSpec } from "@/lib/array-list";
import type { AppDb } from "@/lib/array-reads";

import { arrayReads } from "@/lib/array-reads";
import { readAllPagesResult } from "@/lib/read-all-pages";

import type { SegmentRow } from "../automation/automation-queries";

/** The search, sort and facet of the segments list, shared with its overview. */
export const segmentsSpec: BlockListSpec<SegmentRow> = {
  search: (segment) => `${segment.name} ${segment.description ?? ""}`,
  facet: (segment) => segment.subjectType,
  defaultSort: "name",
  sorts: {
    name: (a, b) => a.name.localeCompare(b.name),
    members: (a, b) => b.memberCount - a.memberCount,
  },
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

/** The segments of the organization. */
export function segmentsFrom(db: AppDb, tenant: string) {
  return readAllPagesResult((page) =>
    db.segments.page({ organizationId: tenant, ...page }),
  ).map((segments) => segments.map(segmentOf));
}

/** The reads module of the `app.segments` entity page (ADR 0894). */
export function segmentsReads(db: AppDb): EntityListReads<SegmentRow> {
  return arrayReads({
    load: (tenant) => segmentsFrom(db, tenant),
    facet: "subjectType",
    spec: segmentsSpec,
    wire: (segment) => segment,
  });
}
