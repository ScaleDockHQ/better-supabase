/**
 * Server-side list state for entities a block returns as a plain list
 * (segments, queues, contracts and the like), which have no table for
 * `defineListQuery`. The URL holds `?q=&f=&sort=&page=`; the server reads it,
 * filters, sorts and pages the rows, and the grid only renders the page it is
 * given.
 */

const BLOCK_LIST_PAGE_SIZE = 25;

export interface BlockListQuery {
  readonly q: string;
  /** The value of the one facet filter, `""` for all. */
  readonly facet: string;
  readonly sort: string;
  /** 1-based. */
  readonly page: number;
}

type RawParams = Readonly<Record<string, string | string[] | undefined>>;

const first = (value: string | string[] | undefined): string =>
  (Array.isArray(value) ? value[0] : value) ?? "";

/** Parses the URL's search params into a list query; a bad page is page 1. */
export function parseBlockList(raw: RawParams): BlockListQuery {
  const page = Math.trunc(Number(first(raw["page"])));

  return {
    q: first(raw["q"]).trim().slice(0, 100),
    facet: first(raw["f"]).slice(0, 60),
    sort: first(raw["sort"]).slice(0, 40),
    page: Number.isInteger(page) && page > 0 ? page : 1,
  };
}

export interface BlockListSpec<Item> {
  /** The text a search matches, lowercased by the caller. */
  readonly search: (item: Item) => string;
  readonly facet?: (item: Item) => string;
  readonly sorts: Readonly<Record<string, (a: Item, b: Item) => number>>;
  readonly defaultSort: string;
}

export interface BlockListResult<Item> {
  readonly rows: readonly Item[];
  /** Rows after the search and the facet filter. */
  readonly total: number;
  readonly page: number;
  readonly pages: number;
  /** Rows per facet value after the search, before the facet filter. */
  readonly facetCounts: Readonly<Record<string, number>>;
}

/** Searches, filters, sorts and pages `items` for one URL state. */
export function applyBlockList<Item>(
  items: readonly Item[],
  query: BlockListQuery,
  spec: BlockListSpec<Item>,
): BlockListResult<Item> {
  const needle = query.q.toLowerCase();

  const searched =
    needle === ""
      ? items
      : items.filter((item) =>
          spec.search(item).toLowerCase().includes(needle),
        );

  const facetCounts: Record<string, number> = {};

  if (spec.facet) {
    for (const item of searched) {
      const value = spec.facet(item);
      facetCounts[value] = (facetCounts[value] ?? 0) + 1;
    }
  }

  const filtered =
    spec.facet && query.facet !== ""
      ? searched.filter((item) => spec.facet?.(item) === query.facet)
      : searched;

  const compare = spec.sorts[query.sort] ?? spec.sorts[spec.defaultSort];
  const sorted = compare ? filtered.toSorted(compare) : filtered;
  const pages = Math.max(1, Math.ceil(sorted.length / BLOCK_LIST_PAGE_SIZE));
  const page = Math.min(query.page, pages);
  const start = (page - 1) * BLOCK_LIST_PAGE_SIZE;

  return {
    rows: sorted.slice(start, start + BLOCK_LIST_PAGE_SIZE),
    total: sorted.length,
    page,
    pages,
    facetCounts,
  };
}
