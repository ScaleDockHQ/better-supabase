import type { AsyncResult } from "better-supabase";
import type {
  FacetOptions,
  FacetResult,
  ListPage,
  PageOptions,
  PageSort,
} from "better-supabase/blocks";
import type { EntityListReads } from "better-supabase/list";

import { ok } from "better-supabase";
import { sortsOf } from "better-supabase/blocks";

import type {
  RecordListPage,
  RecordListUrlQuery,
} from "@/components/record-list/record-list-types";
import type { Mutable } from "@/lib/block-status-list";
import type { bsb } from "@/lib/supabase/server";

import { encodeCursor, pageOptionsOf } from "@/lib/block-page";

/** The route's `db`, as the server client hands it out. */
export type AppDb = Awaited<ReturnType<typeof bsb.cached>>["db"];

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

/** The `page` and `facets` of a block list that takes the organization per call. */
export interface OrganizationReads<Item> {
  page(
    options: PageOptions & { readonly organizationId: string },
  ): AsyncResult<ListPage<Item>>;
  facets(
    options: FacetOptions & { readonly organizationId: string },
  ): AsyncResult<readonly FacetResult[]>;
}

/** A block list with the organization bound, as `pageEntityRows` takes it. */
export function organizationPager<Item>(
  organizationId: string,
  reads: OrganizationReads<Item>,
): EntityPager<Item> {
  return {
    page: (options) => reads.page({ ...options, organizationId }),
    facets: (options) => reads.facets({ ...options, organizationId }),
  };
}

/**
 * The reads module of an `app.*` entity page over a block's `page` and
 * `facets`. The entity's sort, filter and facet names map onto the block's
 * through `map`; the database filters, sorts and pages, so no list is read
 * whole. The organization arrives as the page option `tenantOption` names.
 */
export function blockEntityReads<Item, Wire>({
  pager,
  map,
  wire,
}: {
  pager: (organizationId: string) => EntityPager<Item>;
  map: EntityListMap;
  wire: (item: Item) => Wire;
}): EntityListReads<Wire> {
  const filtersOf = (filters: PageOptions["filters"]) => {
    const mapped: Record<string, readonly string[]> = {};

    for (const [key, values] of Object.entries(filters ?? {})) {
      mapped[map.filters?.[key] ?? key] = values;
    }

    return mapped;
  };

  return {
    async page(options) {
      const tenant = String(options["tenant"] ?? "");

      if (tenant === "") {
        return ok({ items: [], hasMore: false, nextCursor: null });
      }

      const draft: Mutable<PageOptions> = {};

      if (options.q !== undefined) {
        draft.q = options.q;
      }

      if (options.limit !== undefined) {
        draft.limit = options.limit;
      }

      if (options.after !== undefined) {
        draft.after = options.after;
      }

      const filters = filtersOf(options.filters);

      if (Object.keys(filters).length > 0) {
        draft.filters = filters;
      }

      const [term] = sortsOf(options.sort);
      const sort = term === undefined ? undefined : map.sorts[term.by];

      if (sort !== undefined) {
        draft.sort = sort;
      }

      const page = await pager(tenant).page(draft);

      return page.ok
        ? ok({ ...page.data, items: page.data.items.map(wire) })
        : page;
    },
    async facets(options) {
      const tenant = String(options["tenant"] ?? "");

      if (tenant === "") {
        return ok([]);
      }

      const draft: Mutable<FacetOptions> = {};

      if (options.q !== undefined) {
        draft.q = options.q;
      }

      const filters = filtersOf(options.filters);

      if (Object.keys(filters).length > 0) {
        draft.filters = filters;
      }

      const facets = await pager(tenant).facets(draft);

      if (!facets.ok) {
        return facets;
      }

      const urlKeyOf = new Map(
        Object.entries(map.facets ?? {}).map(([key, name]) => [name, key]),
      );

      return ok(
        facets.data.map((facet) => ({
          ...facet,
          facet: urlKeyOf.get(facet.facet) ?? facet.facet,
        })),
      );
    },
  };
}
