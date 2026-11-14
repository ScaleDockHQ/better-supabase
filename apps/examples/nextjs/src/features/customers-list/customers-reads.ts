import type { FacetResult, PageOptions } from "better-supabase/blocks";
import type { EntityListReads, ListQueryInput } from "better-supabase/list";

import type { RecordListPage } from "@/components/record-list/record-list-types";

import { customerList } from "@/lib/lists";

import type { CustomerRow } from "../customers/customer-row";

type Db = Parameters<typeof customerList.run>[0];

/** What the list reads of a customer: the row plus its note count and last note. */
const ROW = {
  select: ["id", "name", "status", "logoPath"],
  // Counted and maxed in the database, in the same request.
  include: { _count: { notes: true }, _max: { notes: { createdAt: true } } },
} as const;

type Sort = "name" | "newest";

const isSort = (value: string | undefined): value is Sort =>
  value === "name" || value === "newest";

type DraftInput = {
  -readonly [K in keyof ListQueryInput<Sort, "status">]: ListQueryInput<
    Sort,
    "status"
  >[K];
};

function queryOf(options: PageOptions) {
  const input: DraftInput = {
    facets: { status: options.filters?.["status"] ?? [] },
  };

  // The customer list sorts by one column, so the first term of a list is the one it applies.
  const first =
    options.sort && "by" in options.sort ? options.sort : options.sort?.[0];

  const sort = first?.by;
  const [after] = options.after ?? [];

  if (options.q !== undefined) {
    input.q = options.q;
  }

  if (isSort(sort)) {
    input.sort = sort;
  }

  if (options.limit !== undefined) {
    input.size = options.limit;
  }

  if (after !== undefined) {
    input.after = after;
  }

  const parsed = customerList.parse(input);

  return parsed.ok ? parsed.value : customerList.defaults;
}

/**
 * The reads module of the `app.customers` entity page (ADR 0893): the keyset
 * `page` and the status `facets` of `customerList`, over the route's `db`. The
 * generated `/api/customers/list` calls it, and so does the overview.
 */
export function customersReads(db: Db) {
  return {
    async page(options: PageOptions) {
      const query = queryOf(options);

      // The facet counts are the other read, so the page skips its own.
      const result = await customerList.run(db, query, {
        ...ROW,
        facetCounts: { facetCounts: {}, facetCountsTruncated: [] },
      });

      if (!result.ok) {
        return result;
      }

      return {
        ok: true as const,
        error: null,
        data: {
          items: result.data.items,
          hasMore: result.data.hasMore,
          nextCursor:
            result.data.nextCursor === null ? null : [result.data.nextCursor],
        },
      };
    },
    async facets(options: Pick<PageOptions, "q" | "filters">) {
      const counted = await customerList.countFacets(db, queryOf(options));

      if (!counted.ok) {
        return counted;
      }

      const capped = counted.data.facetCountsCapped === true;

      const facets: readonly FacetResult[] = Object.entries(
        counted.data.facetCounts,
      ).map(([facet, counts]) => ({
        facet,
        values: Object.entries(counts).map(([value, count]) => ({
          value,
          count: { value: count, exact: !capped },
        })),
      }));

      return { ok: true as const, error: null, data: facets };
    },
  } satisfies EntityListReads<unknown>;
}

/**
 * The first page or a later one as the overview's rows: the generated list
 * query's options in, the list kit's `RecordListPage` out. The overview's
 * `/api/customers/overview` route and the server-rendered first page share it.
 */
export async function readCustomerRows(
  db: Db & { readonly $buckets: { readonly logos: LogoBucket } },
  options: PageOptions,
): Promise<RecordListPage<CustomerRow>> {
  const reads = customersReads(db);

  const [page, facets] = await Promise.all([
    reads.page(options),
    reads.facets(options),
  ]);

  if (!page.ok) {
    throw new Error(page.error.message);
  }

  if (!facets.ok) {
    throw new Error(facets.error.message);
  }

  const counts = Object.fromEntries(
    facets.data.map((facet) => [
      facet.facet,
      Object.fromEntries(
        facet.values.map((entry) => [entry.value, entry.count.value]),
      ),
    ]),
  );

  return {
    items: page.data.items.map((customer): CustomerRow => ({
      id: customer.id,
      name: customer.name,
      status: customer.status,
      logoUrl: customer.logoPath
        ? (db.$buckets.logos.publicUrl(customer.logoPath, {
            transform: "square",
          }).data ?? null)
        : null,
      notes: customer._count.notes,
      lastNoteAt: customer._max.notes.createdAt,
    })),
    nextCursor: page.data.nextCursor?.[0] ?? null,
    facetCounts: counts,
    facetCountsCapped: facets.data.some((facet) =>
      facet.values.some((entry) => !entry.count.exact),
    ),
  };
}

interface LogoBucket {
  publicUrl(
    path: string,
    options: { readonly transform: "square" },
  ): { readonly data: string | null };
}
