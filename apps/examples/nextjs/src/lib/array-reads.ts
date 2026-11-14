import type { AsyncResult } from "better-supabase";
import type { FacetResult, PageOptions } from "better-supabase/blocks";
import type { EntityListReads } from "better-supabase/list";

import { ok } from "better-supabase";

import type { bsb } from "@/lib/supabase/server";

import type { BlockListSpec } from "./array-list";

import { selectBlockList } from "./array-list";

const PAGE_SIZE = 25;

/** The route's `db`, as the server client hands it out. */
export type AppDb = Awaited<ReturnType<typeof bsb.cached>>["db"];

/** The tenant travels as the page option `tenantOption: "tenant"` names. */
export type TenantPageOptions = PageOptions & { readonly tenant?: string };

/** What an array reads module needs to answer `page` and `facets` (ADR 0894). */
export interface ArrayReadsInput<Item, Wire> {
  /** The block's list for the tenant; the whole set the page then filters. */
  readonly load: (tenant: string) => AsyncResult<readonly Item[]>;
  /** The search text, facet and sorts the overview of the same list uses. */
  readonly spec: BlockListSpec<Item>;
  /** The filter name the facet answers to. */
  readonly facet?: string;
  /** The row as JSON; the generated route sends it as it is. */
  readonly wire: (item: Item) => Wire;
}

/** The first sort term a page asks for, as the spec's sort name. */
function sortOf(options: PageOptions): string {
  const { sort } = options;
  const first = sort && "by" in sort ? sort : sort?.[0];

  return first?.by ?? "";
}

/**
 * An entity page's reads over a block that returns its list as an array. The
 * block has no list surface, so the module loads the array, then searches,
 * filters, sorts and pages it in memory with the same spec the overview uses.
 * The cursor is the offset of the next row.
 */
export function arrayReads<Item, Wire>(
  input: ArrayReadsInput<Item, Wire>,
): EntityListReads<Wire> {
  const { facet = "", load, spec, wire } = input;

  return {
    async page(options: TenantPageOptions) {
      if (options.tenant === undefined) {
        return ok({ items: [], hasMore: false, nextCursor: null });
      }

      const loaded = await load(options.tenant);

      if (!loaded.ok) {
        return loaded;
      }

      const { sorted } = selectBlockList(
        loaded.data,
        {
          q: options.q ?? "",
          facet: options.filters?.[facet]?.[0] ?? "",
          sort: sortOf(options),
        },
        spec,
      );

      const limit = options.limit ?? PAGE_SIZE;
      const start = Number(options.after?.[0] ?? 0);
      const end = start + limit;

      return ok({
        items: sorted.slice(start, end).map(wire),
        hasMore: end < sorted.length,
        nextCursor: end < sorted.length ? [String(end)] : null,
      });
    },
    async facets(
      options: Pick<PageOptions, "q" | "filters"> & {
        readonly tenant?: string;
      },
    ) {
      if (options.tenant === undefined) {
        return ok([]);
      }

      const loaded = await load(options.tenant);

      if (!loaded.ok) {
        return loaded;
      }

      const { facetCounts } = selectBlockList(
        loaded.data,
        { q: options.q ?? "", facet: "", sort: "" },
        spec,
      );

      const result: FacetResult = {
        facet,
        values: Object.entries(facetCounts).map(([value, count]) => ({
          value,
          count: { value: count, exact: true },
        })),
      };

      return ok(spec.facet ? [result] : []);
    },
  };
}
