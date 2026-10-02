import { createFromSource } from "fumadocs-core/search/server";

import type { DocsSearchHit } from "./docs-mcp";

import { source } from "./source";

/** The Orama index behind the search dialog and the docs MCP `search_docs` tool. */
export const docsSearch: ReturnType<typeof createFromSource> =
  createFromSource(source);

/** Search results without the `<mark>` highlights the dialog renders. */
export async function searchHits(
  query: string,
  limit: number,
): Promise<readonly DocsSearchHit[]> {
  const results = await docsSearch.search(query);
  return results.slice(0, limit).map((result) => ({
    url: result.url,
    title: result.content.replaceAll(/<\/?mark>/gu, ""),
    type: result.type,
  }));
}
