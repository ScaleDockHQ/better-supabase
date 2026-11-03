import { toolSearch } from "ai";

import type { Result } from "../core/result.ts";

import { DbException } from "../core/db-exception.ts";

/**
 * A tool catalog an app keeps in Postgres: rows with an embedding column that
 * `search` ranks by similarity under the caller's RLS, so a user only discovers
 * tools they may call. A knowledge or `searchTool` client over the catalog
 * table fits.
 */
export interface ToolCatalog {
  search(
    query: string,
    options: { readonly limit: number },
  ): PromiseLike<Result<readonly { readonly name: string }[]>>;
}

export interface ToolSearchFromOptions {
  readonly catalog: ToolCatalog;
  /** The tools one search discovers. Defaults to 5, as `toolSearch` does. */
  readonly maxResults?: number;
}

const DEFAULT_MAX = 5;

/**
 * The AI SDK's `toolSearch` with the catalog's ranking in place of keyword
 * matching. Names the catalog returns that are not deferred tools of the
 * generation are ignored by the SDK. A catalog error throws a `DbException`.
 */
export function toolSearchFrom(
  options: ToolSearchFromOptions,
): ReturnType<typeof toolSearch> {
  const maxResults = options.maxResults ?? DEFAULT_MAX;

  return toolSearch({
    maxResults,
    search: async ({ query }) => {
      const found = await options.catalog.search(query, { limit: maxResults });

      if (!found.ok) {
        throw new DbException(found.error);
      }

      return found.data.map((row) => row.name);
    },
  });
}
