import type { RecordListState } from "better-supabase/react";

/** What a list query's parsed URL state holds, whatever the entity. */
export interface RecordListUrlQuery {
  readonly q?: string;
  readonly sort: string;
  readonly after?: string;
  readonly facets: Readonly<Record<string, readonly string[] | undefined>>;
}

/** The list state `useRecordListState` returns for one entity. */
export type RecordListUrl = RecordListState<RecordListUrlQuery>;

/** The JSON a list route answers with, and the server passes as the first page. */
export interface RecordListPage<Row> {
  readonly items: readonly Row[];
  readonly nextCursor?: string | null;
  /** Rows per facet value, by facet key. */
  readonly facetCounts?: Readonly<
    Record<string, Readonly<Record<string, number>>>
  >;
  /** The counts stopped at the scan cap, so each one is a lower bound. */
  readonly facetCountsCapped?: boolean;
}

export interface RecordListFacet {
  /** The facet key of the list query. */
  readonly key: string;
  readonly label: string;
  /** The label of one facet value. */
  readonly valueLabel: (value: string) => string;
}

export interface RecordListSort {
  readonly value: string;
  readonly label: string;
}
