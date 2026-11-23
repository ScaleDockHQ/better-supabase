import type { PostgresCacheSqlOptions } from "./sql.ts";

/** The names `postgresCacheSql` and `postgresCacheStore` agree on. */
export interface PostgresCacheNames {
  readonly schema: string;
  readonly entriesTable: string;
  readonly tagsTable: string;
  readonly getFunction: string;
  readonly markTagsFunction: string;
}

export function postgresCacheNames(
  options: Omit<PostgresCacheSqlOptions, "prune"> = {},
): PostgresCacheNames {
  const prefix = options.functionPrefix ?? "bsb_cache";

  return {
    schema: options.schema ?? "public",
    entriesTable: options.entriesTable ?? "bsb_cache_entries",
    tagsTable: options.tagsTable ?? "bsb_cache_tags",
    getFunction: `${prefix}_get`,
    markTagsFunction: `${prefix}_mark_tags`,
  };
}
