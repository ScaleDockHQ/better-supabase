import { createFromSource } from "fumadocs-core/search/server";
import { cacheLife } from "next/cache";

import type { DocsSearchHit } from "./docs-mcp";

import { source } from "./source";

/** The Orama index behind the search dialog and the docs MCP `search_docs` tool. */
const docsSearch = createFromSource(source);

type SearchResults = Awaited<ReturnType<typeof docsSearch.search>>;

/** The index only changes with a deploy, so each query's results are cached for good. */
export async function search(query: string): Promise<SearchResults> {
  "use cache";
  cacheLife("max");
  return docsSearch.search(query);
}

/** Search results without the `<mark>` highlights the dialog renders. */
export async function searchHits(
  query: string,
  limit: number,
): Promise<readonly DocsSearchHit[]> {
  const results = await search(query);
  return results.slice(0, limit).map((result) => ({
    url: result.url,
    title: result.content.replaceAll(/<\/?mark>/gu, ""),
    type: result.type,
  }));
}
