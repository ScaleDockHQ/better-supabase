import { createLoader } from "nuqs/server";

import type { RecordListUrlQuery } from "@/components/record-list/record-list-types";
import type { Mutable } from "@/lib/block-status-list";

import { blockOverviewParsers } from "@/lib/block-overview-params";

const SEARCH_MAX = 100;

const loadBlockOverviewParams = createLoader(blockOverviewParsers);

type RawParams = Readonly<Record<string, string | string[] | undefined>>;

/**
 * The URL state of a block overview: `?q=&f=&sort=&after=`, read with the same
 * parsers the client grid writes with (`blockOverviewParsers`). `f` is held as
 * the facet `f`; `after` is the keyset cursor of the block's `page`. The
 * overview maps these names onto the block's own (`pageEntityRows`).
 */
export function parseBlockList(raw: RawParams): RecordListUrlQuery {
  const parsed = loadBlockOverviewParams(raw);
  const q = parsed.q.trim().slice(0, SEARCH_MAX);
  const facet = parsed.f.slice(0, 60);

  const query: Mutable<RecordListUrlQuery> = {
    sort: parsed.sort.slice(0, 40),
    facets: facet === "" ? {} : { f: [facet] },
  };

  if (q !== "") {
    query.q = q;
  }

  if (parsed.after !== "") {
    query.after = parsed.after;
  }

  return query;
}
