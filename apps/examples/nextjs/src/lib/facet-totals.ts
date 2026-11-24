import type { FacetResult } from "better-supabase/blocks";

/** The count of each value of the facet `name`; a facet the read lacks is empty. */
export function facetTotals(
  facets: readonly FacetResult[],
  name: string,
): Readonly<Record<string, number>> {
  const facet = facets.find((candidate) => candidate.facet === name);

  return Object.fromEntries(
    (facet?.values ?? []).map((value) => [value.value, value.count.value]),
  );
}

/** The sum of the counts of a facet's values. */
export function totalOf(totals: Readonly<Record<string, number>>): number {
  return Object.values(totals).reduce((sum, count) => sum + count, 0);
}
