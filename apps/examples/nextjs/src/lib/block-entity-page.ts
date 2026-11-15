import type { AsyncResult } from "better-supabase";
import type {
  FacetOptions,
  FacetResult,
  ListPage,
  PageOptions,
  PageSort,
} from "better-supabase/blocks";

import type {
  RecordListPage,
  RecordListUrlQuery,
} from "@/components/record-list/record-list-types";
import type { Mutable } from "@/lib/block-status-list";

import { encodeCursor, pageOptionsOf } from "@/lib/block-page";

/** The `page` and `facets` reads of a block list, with its tenant bound. */
export interface EntityPager<Item> {
  page(options: PageOptions): AsyncResult<ListPage<Item>>;
  facets(options: FacetOptions): AsyncResult<readonly FacetResult[]>;
}

/** How a list's URL names map onto the block list's own names. */
export interface EntityListMap {
  /** The sort each URL `sort` value stands for. */
  readonly sorts: Readonly<Record<string, PageSort | readonly PageSort[]>>;
  /** The block filter of a URL facet key; the key itself when absent. */
  readonly filters?: Readonly<Record<string, string>>;
  /** The block facet that counts a URL facet key; the key itself when absent. */
  readonly facets?: Readonly<Record<string, string>>;
  /** Block filters that apply while the query sets none of that name. */
  readonly defaultFilters?: Readonly<Record<string, readonly string[]>>;
}

/**
 * One page of a block list for a parsed list query: the search text, the sort,
 * the facet selections and the cursor go to the block's `page`, and `facets`
 * counts each facet under the same filters, so the database does the work.
 * `rowsOf` turns the page's items into the serializable rows the list sends.
 */
export async function pageEntityRows<Item, Row>({
  pager,
  map,
  query,
  pageSize,
  rowsOf,
}: {
  pager: EntityPager<Item>;
  map: EntityListMap;
  query: RecordListUrlQuery;
  pageSize: number;
  rowsOf: (items: readonly Item[]) => readonly Row[] | Promise<readonly Row[]>;
}): Promise<RecordListPage<Row>> {
  const filters: Record<string, readonly string[]> = {};

  for (const [key, values] of Object.entries(query.facets)) {
    if (values !== undefined && values.length > 0) {
      filters[map.filters?.[key] ?? key] = values;
    }
  }

  for (const [name, values] of Object.entries(map.defaultFilters ?? {})) {
    filters[name] ??= values;
  }

  const options: Mutable<PageOptions> = pageOptionsOf(query, pageSize, filters);
  const sort = map.sorts[query.sort];

  if (sort !== undefined) {
    options.sort = sort;
  }

  const urlKeyOf = new Map(
    Object.entries(map.facets ?? {}).map(([key, name]) => [name, key]),
  );

  const facetOptions: Mutable<FacetOptions> = {};

  if (options.q !== undefined) {
    facetOptions.q = options.q;
  }

  if (options.filters !== undefined) {
    facetOptions.filters = options.filters;
  }

  const [page, facets] = await Promise.all([
    pager.page(options).orThrow(),
    pager.facets(facetOptions).orThrow(),
  ]);

  const facetCounts: Record<string, Record<string, number>> = {};

  for (const facet of facets) {
    const key = urlKeyOf.get(facet.facet) ?? facet.facet;
    facetCounts[key] = Object.fromEntries(
      facet.values.map((value) => [value.value, value.count.value]),
    );
  }

  return {
    items: await rowsOf(page.items),
    nextCursor: encodeCursor(page.nextCursor),
    facetCounts,
    facetCountsCapped: facets.some((facet) =>
      facet.values.some((value) => !value.count.exact),
    ),
  };
}
