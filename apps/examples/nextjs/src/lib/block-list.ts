import type {
  RecordListPage,
  RecordListUrlQuery,
} from "@/components/record-list/record-list-types";
import type { BlockList } from "@/lib/block-list-url";

export { defineBlockList } from "@/lib/block-list-url";

export type { BlockList, BlockListConfig } from "@/lib/block-list-url";

export interface BlockListSpec<Row> {
  /** The text a search matches, lower-cased by the caller or not. */
  readonly text: (row: Row) => readonly (string | null | undefined)[];
  /** The value of each facet for a row. */
  readonly facets: Readonly<Record<string, (row: Row) => string>>;
  readonly sorts: Readonly<Record<string, (a: Row, b: Row) => number>>;
}

/**
 * Searches, filters, sorts and pages `rows` for a parsed query, with the count
 * per facet value of the rows the search matches.
 */
export function pageBlockRows<Row extends { readonly id: string }>(
  list: BlockList,
  spec: BlockListSpec<Row>,
  rows: readonly Row[],
  query: RecordListUrlQuery,
): RecordListPage<Row> {
  const needle = query.q?.trim().toLowerCase() ?? "";

  const matched =
    needle === ""
      ? rows
      : rows.filter((row) =>
          spec.text(row).some((text) => text?.toLowerCase().includes(needle)),
        );

  const facetCounts: Record<string, Record<string, number>> = {};

  for (const [key, valueOf] of Object.entries(spec.facets)) {
    const counts: Record<string, number> = {};

    for (const row of matched) {
      const value = valueOf(row);
      counts[value] = (counts[value] ?? 0) + 1;
    }

    facetCounts[key] = counts;
  }

  const filtered = matched.filter((row) =>
    Object.entries(query.facets).every(([key, values]) => {
      const valueOf = spec.facets[key];

      return (
        valueOf === undefined ||
        values === undefined ||
        values.length === 0 ||
        values.includes(valueOf(row))
      );
    }),
  );

  const compare = spec.sorts[query.sort] ?? spec.sorts[list.config.defaultSort];
  const sorted = compare ? filtered.toSorted(compare) : filtered;

  const start = Math.trunc(Number(query.after ?? "0")) || 0;
  const end = start + list.config.pageSize;

  return {
    items: sorted.slice(start, end),
    nextCursor: end < sorted.length ? String(end) : null,
    facetCounts,
    facetCountsCapped: false,
  };
}
