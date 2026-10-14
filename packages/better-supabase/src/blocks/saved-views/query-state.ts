import type { FilterQuery } from "../../list/filter-query.ts";
import type { ListQueryInput } from "../../list/list-query.ts";

/**
 * The URL state of a list as nuqs returns it from
 * `useQueryStates(list.nuqs(createParser))`: one key per parser, `null`
 * when the parameter is absent.
 */
export type ListUrlState = Readonly<Record<string, unknown>>;

const RESERVED = new Set(["q", "sort", "page", "after", "size", "filter"]);

const isStrings = (value: unknown): value is readonly string[] =>
  Array.isArray(value) && value.every((item) => typeof item === "string");

const isFilter = (value: unknown): value is FilterQuery =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** A list's URL state as the typed query a view stores, without the page. */
export function queryFromUrlState(
  state: ListUrlState,
): ListQueryInput<string, string> {
  const facets: Record<string, readonly string[]> = {};
  for (const [key, value] of Object.entries(state)) {
    if (!RESERVED.has(key) && isStrings(value) && value.length > 0) {
      facets[key] = value;
    }
  }
  const q = state["q"];
  const sort = state["sort"];
  const size = state["size"];
  const filter = state["filter"];
  return {
    ...(typeof q === "string" && q !== "" && { q }),
    ...(typeof sort === "string" && { sort }),
    ...(typeof size === "number" && { size }),
    ...(isFilter(filter) && { filter }),
    ...(Object.keys(facets).length > 0 && { facets }),
  };
}

/**
 * The URL state that opens a view's query: every key in `keys` (the
 * current state's), `null` unless the query sets it, so applying a view
 * clears what the previous one set. The page goes back to the first.
 */
export function urlStateFromQuery(
  query: ListQueryInput<string, string> | undefined,
  keys: readonly string[],
): Record<string, unknown> {
  const facets: Readonly<Record<string, readonly string[] | undefined>> =
    query?.facets ?? {};
  const next: Record<string, unknown> = {};
  for (const key of keys) {
    switch (key) {
      case "q":
        next[key] = query?.q ?? null;
        break;
      case "sort":
        next[key] = query?.sort ?? null;
        break;
      case "size":
        next[key] = query?.size ?? null;
        break;
      case "filter":
        next[key] = query?.filter ?? null;
        break;
      case "page":
      case "after":
        next[key] = null;
        break;
      default:
        next[key] = facets[key]?.length ? facets[key] : null;
    }
  }
  return next;
}

function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (typeof value === "object" && value !== null) {
    return Object.fromEntries(
      Object.entries(value)
        .filter(([, item]) => item !== undefined && item !== null)
        .toSorted(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
        .map(([key, item]) => [key, canonical(item)]),
    );
  }
  return value;
}

/** Whether two stored queries select the same rows in the same order. */
export function sameQuery(
  a: ListQueryInput<string, string> | undefined,
  b: ListQueryInput<string, string> | undefined,
): boolean {
  const strip = (
    query: ListQueryInput<string, string> | undefined,
  ): unknown => {
    if (!query) return {};
    const { page: _page, after: _after, facets, ...rest } = query;
    const kept = Object.entries(facets ?? {}).filter(
      ([, values]) => values !== undefined && values.length > 0,
    );
    return canonical(
      kept.length > 0 ? { ...rest, facets: Object.fromEntries(kept) } : rest,
    );
  };
  return JSON.stringify(strip(a)) === JSON.stringify(strip(b));
}
