import type {
  RecordListPage,
  RecordListUrlQuery,
} from "@/components/record-list/record-list-types";

/**
 * A list over a block's read method. `defineListQuery` runs over the app's own
 * tables; a block table has no list query, so the server reads the block's rows
 * for the page's own filters, then searches, filters, sorts and pages them here
 * (EX-901). The definition is plain data, shared by the server and the client
 * hook, and satisfies the `RecordListUrl` shape `useRecordListState` takes.
 */
type Writable<T> = { -readonly [K in keyof T]: T[K] };

export interface BlockListConfig {
  /** The facet keys; each holds a comma separated list in the URL. */
  readonly facets: readonly string[];
  readonly sorts: readonly string[];
  readonly defaultSort: string;
  readonly pageSize: number;
}

export interface BlockList {
  readonly config: BlockListConfig;
  readonly defaults: RecordListUrlQuery;
  readonly facets: readonly { readonly key: string }[];
  parse(input: URLSearchParams): {
    readonly ok: true;
    readonly value: RecordListUrlQuery;
  };
  toSearchParams(query: Partial<RecordListUrlQuery>): URLSearchParams;
}

export function defineBlockList(config: BlockListConfig): BlockList {
  const defaults: RecordListUrlQuery = { sort: config.defaultSort, facets: {} };

  return {
    config,
    defaults,
    facets: config.facets.map((key) => ({ key })),
    parse(input) {
      const sort = input.get("sort");
      const q = input.get("q");
      const after = input.get("after");

      const facets: Record<string, readonly string[]> = {};

      for (const key of config.facets) {
        const raw = input.get(key);

        if (raw !== null && raw !== "") {
          facets[key] = raw.split(",");
        }
      }

      const value: Writable<RecordListUrlQuery> = {
        sort:
          sort !== null && config.sorts.includes(sort)
            ? sort
            : config.defaultSort,
        facets,
      };

      if (q !== null && q !== "") {
        value.q = q;
      }

      if (after !== null && after !== "") {
        value.after = after;
      }

      return { ok: true, value };
    },
    toSearchParams(query) {
      const params = new URLSearchParams();

      if (query.q !== undefined && query.q !== "") {
        params.set("q", query.q);
      }

      if (query.sort !== undefined && query.sort !== config.defaultSort) {
        params.set("sort", query.sort);
      }

      if (query.after !== undefined && query.after !== "") {
        params.set("after", query.after);
      }

      for (const key of config.facets) {
        const value = query.facets?.[key];

        if (value !== undefined && value.length > 0) {
          params.set(key, value.join(","));
        }
      }

      return params;
    },
  };
}

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
