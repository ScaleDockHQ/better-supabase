import type { RecordListUrl } from "better-supabase/react";

/**
 * What a simple list's URL holds: a search, one sort, a cursor and facet
 * values.
 */
export interface SimpleListQuery {
  readonly q?: string;
  readonly sort: string;
  readonly after?: string;
  readonly facets: Readonly<Record<string, readonly string[] | undefined>>;
}

export interface SimpleListConfig {
  /** Facet keys; each is one URL key holding comma-separated values. */
  readonly facets: readonly string[];
  readonly sorts: readonly string[];
  readonly defaultSort: string;
}

export interface SimpleList extends RecordListUrl<SimpleListQuery> {
  readonly config: SimpleListConfig;
}

const SEARCH_MAX = 100;

/**
 * The URL contract of a list that is not a table:
 * `?q=&sort=&after=&<facet>=a,b`, the shape `useRecordListState` and the list
 * kit read. The list route parses the same params with `parse`, so the browser
 * and the server agree.
 */
export function defineSimpleList(config: SimpleListConfig): SimpleList {
  const defaults: SimpleListQuery = { sort: config.defaultSort, facets: {} };

  return {
    config,
    defaults,
    facets: config.facets.map((key) => ({ key })),
    parse(input) {
      const sort = input.get("sort");
      const q = input.get("q")?.trim().slice(0, SEARCH_MAX);
      const after = input.get("after") ?? undefined;

      const facets = Object.fromEntries(
        config.facets.flatMap((key) => {
          const values = input
            .get(key)
            ?.split(",")
            .filter((value) => value !== "");

          return values === undefined || values.length === 0
            ? []
            : [[key, values] as const];
        }),
      );

      const base: SimpleListQuery = {
        sort:
          sort !== null && config.sorts.includes(sort)
            ? sort
            : config.defaultSort,
        facets,
      };

      const searched = q === undefined || q === "" ? base : { ...base, q };

      return {
        ok: true,
        value: after === undefined ? searched : { ...searched, after },
      };
    },
    toSearchParams(query) {
      const params = new URLSearchParams();

      if (query.q !== undefined && query.q !== "") {
        params.set("q", query.q);
      }

      if (query.sort !== undefined && query.sort !== config.defaultSort) {
        params.set("sort", query.sort);
      }

      if (query.after !== undefined) {
        params.set("after", query.after);
      }

      for (const [key, values] of Object.entries(query.facets ?? {})) {
        if (values !== undefined && values.length > 0) {
          params.set(key, values.join(","));
        }
      }

      return params;
    },
  };
}
