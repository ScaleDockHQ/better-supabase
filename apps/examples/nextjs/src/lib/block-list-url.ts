import type { RecordListUrlQuery } from "@/components/record-list/record-list-types";

/**
 * The URL state of a list over a block's page methods. The definition is plain
 * data, shared by the server and the client hook, and satisfies the
 * `RecordListUrl` shape `useRecordListState` takes. The server hands the parsed
 * query to the block's `page` and `facets` (`pageEntityRows`).
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
