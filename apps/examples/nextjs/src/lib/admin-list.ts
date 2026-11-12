import { parseAsArrayOf, parseAsString } from "nuqs/server";

/** What an admin list's URL holds, parsed: `?q=&status=&sort=&after=`. */
export interface AdminListQuery {
  readonly q?: string;
  readonly sort: string;
  readonly after?: string;
  readonly facets: Readonly<Record<string, readonly string[] | undefined>>;
}

interface AdminListConfig<Sort extends string> {
  /** Each facet key with the values the list accepts; none accepts any. */
  readonly facets: Readonly<Record<string, readonly string[]>>;
  /** Every sort is a time column with `id` as the tie break. */
  readonly sorts: readonly Sort[];
  readonly defaultSort: NoInfer<Sort>;
  readonly pageSize: number;
}

const MAX_SEARCH = 100;

/**
 * A list over the tables of the admin and platform pages, which have no
 * `defineListQuery` table module (they live in `better_supabase`). It has the
 * shape `useRecordListState` takes, so the list kit renders it, and the same
 * `parse` runs in the list route and in the client.
 */
export function defineAdminList<Sort extends string>(
  config: AdminListConfig<Sort>,
) {
  const facetKeys = Object.keys(config.facets);

  const defaults: AdminListQuery = { sort: config.defaultSort, facets: {} };

  return {
    ...config,
    defaults,
    facetKeys,
    facets: facetKeys.map((key) => ({ key })),
    parse(
      input: URLSearchParams,
    ):
      | { readonly ok: true; readonly value: AdminListQuery }
      | { readonly ok: false } {
      const sort = input.get("sort") ?? config.defaultSort;

      if (!config.sorts.some((known) => known === sort)) {
        return { ok: false };
      }

      const facets: Record<string, readonly string[]> = {};

      for (const key of facetKeys) {
        const raw = input.get(key);

        if (raw === null || raw === "") {
          continue;
        }

        const accepted = config.facets[key] ?? [];

        // An empty list accepts any value, for a facet whose values the data sets.
        const values = raw
          .split(",")
          .filter(
            (value) =>
              value.length <= MAX_SEARCH &&
              (accepted.length === 0 || accepted.includes(value)),
          );

        if (values.length === 0) {
          return { ok: false };
        }

        facets[key] = values;
      }

      const q = input.get("q")?.trim().slice(0, MAX_SEARCH);
      const after = input.get("after");

      const withSearch = q ? { sort, facets, q } : { sort, facets };
      const value = after ? { ...withSearch, after } : withSearch;

      return { ok: true, value };
    },
    toSearchParams(query: Partial<AdminListQuery>): URLSearchParams {
      const params = new URLSearchParams();

      if (query.q) {
        params.set("q", query.q);
      }

      if (query.sort && query.sort !== config.defaultSort) {
        params.set("sort", query.sort);
      }

      for (const key of facetKeys) {
        const values = query.facets?.[key];

        if (values && values.length > 0) {
          params.set(key, values.join(","));
        }
      }

      if (query.after) {
        params.set("after", query.after);
      }

      return params;
    },
    /** Nuqs parsers: one key per list parameter, for `useQueryStates`. */
    parsers() {
      return {
        q: parseAsString,
        sort: parseAsString,
        after: parseAsString,
        page: parseAsString,
        ...Object.fromEntries(
          facetKeys.map((key) => [key, parseAsArrayOf(parseAsString)]),
        ),
      };
    },
  };
}

export type AdminList = ReturnType<typeof defineAdminList>;
