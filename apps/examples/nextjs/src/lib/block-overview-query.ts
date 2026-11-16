import type { RecordListUrlQuery } from "@/components/record-list/record-list-types";
import type { Mutable } from "@/lib/block-status-list";

const SEARCH_MAX = 100;

type RawParams = Readonly<Record<string, string | string[] | undefined>>;

const first = (value: string | string[] | undefined): string =>
  (Array.isArray(value) ? value[0] : value) ?? "";

/**
 * The URL state of a block overview: `?q=&f=&sort=&after=`. `f` is the one
 * facet filter, held as the facet `f`; `after` is the keyset cursor of the
 * block's `page`. The overview maps these names onto the block's own
 * (`pageEntityRows`).
 */
export function parseBlockList(raw: RawParams): RecordListUrlQuery {
  const q = first(raw["q"]).trim().slice(0, SEARCH_MAX);
  const facet = first(raw["f"]).slice(0, 60);
  const after = first(raw["after"]);

  const query: Mutable<RecordListUrlQuery> = {
    sort: first(raw["sort"]).slice(0, 40),
    facets: facet === "" ? {} : { f: [facet] },
  };

  if (q !== "") {
    query.q = q;
  }

  if (after !== "") {
    query.after = after;
  }

  return query;
}
