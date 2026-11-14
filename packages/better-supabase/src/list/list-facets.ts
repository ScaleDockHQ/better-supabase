import { AsyncResult } from "../core/result.ts";

interface FacetColumn {
  readonly key: string;
  readonly column: string;
  readonly values?: readonly string[];
}

interface FacetCountResult<F extends string> {
  readonly facetCounts: Readonly<Record<F, Readonly<Record<string, number>>>>;
  readonly facetCountsTruncated: readonly F[];
  readonly facetCountsCapped?: boolean;
}

type FacetRead = (request: Record<string, unknown>) => AsyncResult<unknown>;

interface FacetRepository {
  page: (input: Record<string, unknown>) => AsyncResult<unknown>;
  aggregate: (input: Record<string, unknown>) => AsyncResult<unknown>;
  list: (input: Record<string, unknown>) => AsyncResult<unknown>;
}

export interface OpenListRun {
  readonly page: AsyncResult<unknown>;
  readonly repository: FacetRepository;
  readonly extraWhere: Record<string, unknown> | undefined;
  readonly options: Record<string, unknown>;
  readonly cachedCounts: FacetCountResult<string> | undefined;
  /** The per-call `facetCountMode`, when the caller set one. */
  readonly facetCountMode: "exact" | "capped" | undefined;
}

function cachedFacetCounts(
  value: unknown,
): FacetCountResult<string> | undefined {
  if (
    typeof value !== "object" ||
    value === null ||
    !("facetCounts" in value) ||
    !("facetCountsTruncated" in value)
  ) {
    return undefined;
  }

  // SAFETY: the fields above are the cache shape `run` accepts.
  return value as FacetCountResult<string>;
}

/** Starts the page read and separates a caller-supplied facet count cache. */
export function openListRun(input: {
  readonly table: unknown;
  readonly base: Record<string, unknown>;
  readonly extra: Record<string, unknown> | undefined;
  readonly cursor: boolean;
  /** When false, the repository is prepared and the page is not requested. */
  readonly page?: boolean;
  readonly combine: (
    left: Record<string, unknown> | undefined,
    right: Record<string, unknown> | undefined,
  ) => Record<string, unknown> | undefined;
}): OpenListRun {
  // SAFETY: the value is the table repository. The list only calls page, list and aggregate.
  const repository = input.table as FacetRepository;
  const parsed = input.extra ?? {};

  // SAFETY: where on the list input is the filter record the page combines.
  const extraWhere = parsed["where"] as Record<string, unknown> | undefined;

  const cachedCounts = cachedFacetCounts(parsed["facetCounts"]);

  const {
    where: _where,
    count,
    select,
    include,
    facetCounts: _facetCounts,
    facetCountMode,
    ...options
  } = parsed;

  // SAFETY: args().where is the same filter record.
  const baseWhere = input.base["where"] as Record<string, unknown> | undefined;

  const combined = input.combine(extraWhere, baseWhere);

  const pageInput: Record<string, unknown> = { ...options, ...input.base };

  if (select !== undefined) {
    pageInput["select"] = select;
  }

  if (include !== undefined) {
    pageInput["include"] = include;
  }

  if (!input.cursor) {
    pageInput["count"] = count ?? input.base["count"];
  }

  if (combined) {
    pageInput["where"] = combined;
  }

  const page =
    input.page === false
      ? AsyncResult.ok(undefined)
      : repository.page(pageInput);

  return {
    page,
    repository,
    extraWhere,
    options,
    cachedCounts,
    facetCountMode:
      facetCountMode === "exact" || facetCountMode === "capped"
        ? facetCountMode
        : undefined,
  };
}

/**
 * A cache key for facet counts. Page, cursor and size are left out, so the
 * counts stay valid while the reader moves through the list.
 */
export function facetCacheKey(query: {
  readonly q?: string;
  readonly facets?: Readonly<Record<string, readonly string[] | undefined>>;
  readonly filter?: unknown;
  readonly timeZone?: string;
}): string {
  const source = query.facets ?? {};

  const facets = Object.keys(source)
    .toSorted()
    .map((key) => [key, [...(source[key] ?? [])].toSorted()]);

  return JSON.stringify({
    q: query.q ?? null,
    facets,
    filter: query.filter ?? null,
    timeZone: query.timeZone ?? null,
  });
}

/**
 * Exact mode groups every matching row. Capped mode reads at most `scanCap`
 * rows per facet, so a large tenant is not scanned.
 */
export function loadFacetCounts<F extends string>(input: {
  readonly enabled: boolean;
  readonly mode: "exact" | "capped";
  readonly facets: readonly (FacetColumn & { readonly key: F })[];
  readonly facetLimit: number;
  readonly scanCap: number;
  readonly options: Record<string, unknown>;
  readonly filterFor: (
    facet: FacetColumn & { readonly key: F },
  ) => Record<string, unknown> | undefined;
  readonly list: FacetRead;
  readonly aggregate: FacetRead;
  readonly countsOf: (
    facet: FacetColumn & { readonly key: F },
    groups: readonly Record<string, unknown>[],
  ) => Record<string, number>;
}): AsyncResult<FacetCountResult<F>> {
  const { facets } = input;

  if (!input.enabled || facets.length === 0) {
    return AsyncResult.ok({
      // SAFETY: there are no facets, so the mapped count record is empty.
      facetCounts: {} as FacetCountResult<F>["facetCounts"],
      facetCountsTruncated: [],
    });
  }

  if (input.mode === "capped") {
    const reads = facets.map((facet) => {
      const request: Record<string, unknown> = {
        ...input.options,
        select: [facet.column],
        limit: input.scanCap,
      };

      const filter = input.filterFor(facet);

      if (filter) {
        request["where"] = filter;
      }

      return input.list(request);
    });

    return AsyncResult.from(async () => {
      const results = await Promise.all(reads);
      const facetCounts: Record<string, Record<string, number>> = {};
      const truncated: F[] = [];
      let capped = false;

      for (const [index, facet] of facets.entries()) {
        const result = results[index]!;

        if (!result.ok) {
          return result;
        }

        // SAFETY: list returns one row per read, with the facet column.
        const rows = result.data as Record<string, unknown>[];

        if (rows.length >= input.scanCap) {
          capped = true;
        }

        const groups = rows.map((row) => ({
          [facet.column]: row[facet.column],
          _count: 1,
        }));

        const counts = input.countsOf(facet, groups);

        const ranked = Object.entries(counts).toSorted(
          (left, right) =>
            right[1] - left[1] || left[0].localeCompare(right[0]),
        );

        if (ranked.length > input.facetLimit) {
          truncated.push(facet.key);
          facetCounts[facet.key] = Object.fromEntries(
            ranked.slice(0, input.facetLimit),
          );
        } else {
          facetCounts[facet.key] = counts;
        }
      }

      // SAFETY: keys are the facet names this function was given.
      const counts = facetCounts as FacetCountResult<F>["facetCounts"];

      const data: FacetCountResult<F> = {
        facetCounts: counts,
        facetCountsTruncated: truncated,
      };

      if (capped) {
        return {
          ok: true as const,
          data: { ...data, facetCountsCapped: true },
          error: null,
        };
      }

      return { ok: true as const, data, error: null };
    });
  }

  const counted = facets.map((facet) => {
    const request: Record<string, unknown> = {
      ...input.options,
      groupBy: [facet.column],
      _count: true,
      orderBy: [{ _count: "desc" }, { [facet.column]: "asc" }],
      limit: input.facetLimit + 1,
    };

    const filter = input.filterFor(facet);

    if (filter) {
      request["where"] = filter;
    }

    return input.aggregate(request);
  });

  return AsyncResult.from(async () => {
    const results = await Promise.all(counted);
    const facetCounts: Record<string, Record<string, number>> = {};
    const truncated: F[] = [];

    for (const [index, facet] of facets.entries()) {
      const result = results[index]!;

      if (!result.ok) {
        return result;
      }

      // SAFETY: aggregate with groupBy returns one row per group.
      const rows = result.data as Record<string, unknown>[];

      if (rows.length > input.facetLimit) {
        truncated.push(facet.key);
      }

      facetCounts[facet.key] = input.countsOf(
        facet,
        rows.slice(0, input.facetLimit),
      );
    }

    // SAFETY: keys are the facet names this function was given.
    const counts = facetCounts as FacetCountResult<F>["facetCounts"];

    return {
      ok: true as const,
      data: { facetCounts: counts, facetCountsTruncated: truncated },
      error: null,
    };
  });
}
