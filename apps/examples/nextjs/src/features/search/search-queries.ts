import "server-only";
import { cacheLife } from "next/cache";

import { bsb } from "@/lib/supabase/server";

/** Hits per query: the facet counts read this many, so they stop at it. */
export const SEARCH_PAGE_SIZE = 100;

export interface SearchRow {
  readonly subjectType: string;
  readonly subjectId: string;
  readonly title: string | null;
  readonly url: string | null;
  readonly snippet: string | null;
}

export interface SearchPageData {
  /** The matches of `type`, or of every type. */
  readonly rows: readonly SearchRow[];
  /** Matches per subject type before `type` narrows them, best type first. */
  readonly facets: readonly { readonly type: string; readonly count: number }[];
  /** The search returned `SEARCH_PAGE_SIZE` hits, so counts are lower bounds. */
  readonly capped: boolean;
}

const row = (hit: {
  subjectType: string;
  subjectId: string;
  title: string | null;
  url: string | null;
  snippet?: string | null | undefined;
}): SearchRow => ({
  subjectType: hit.subjectType,
  subjectId: hit.subjectId,
  title: hit.title,
  url: hit.url,
  snippet: hit.snippet ?? null,
});

/**
 * `search(q)` as the caller: Postgres ranks the matches and drops what RLS
 * hides. The type facets come from one search over every type; a chosen type
 * adds a second search over that type alone, so its rows are not limited to the
 * share they had in the mixed list. The two run in one wave.
 */
export async function searchRecords(
  q: string,
  type: string | undefined,
): Promise<SearchPageData> {
  "use cache: private";
  // Rows of every table feed the index, so no one tag covers a write: keep an answer only briefly.
  cacheLife("seconds");

  if (q.trim() === "") {
    return { rows: [], facets: [], capped: false };
  }

  const { db } = await bsb.cached();

  const [all, narrowed] = await Promise.all([
    db.search.search({ q, query: { limit: SEARCH_PAGE_SIZE } }).orThrow(),
    type === undefined
      ? Promise.resolve(undefined)
      : db.search
          .search({ q, query: { limit: SEARCH_PAGE_SIZE, types: [type] } })
          .orThrow(),
  ]);

  const counts = new Map<string, number>();

  for (const hit of all) {
    counts.set(hit.subjectType, (counts.get(hit.subjectType) ?? 0) + 1);
  }

  return {
    rows: (narrowed ?? all).map(row),
    facets: [...counts].map(([facet, count]) => ({ type: facet, count })),
    capped: all.length >= SEARCH_PAGE_SIZE,
  };
}
