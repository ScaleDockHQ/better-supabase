---
'better-supabase': minor
---

List facet counts and count modes. `defineListQuery(sb, table, { facetCounts: true })` makes `run`
return `page.facetCounts` (rows per facet value, where each facet applies the other facets'
selections) from one grouped aggregate that runs in parallel with the page: 2 calls, 1 wave.
`count: 'exact' | 'planned' | 'estimated'` can be set in the config or per `run`. `ListExtra.include`
now takes the relation map (`{ notes: true, _count: { notes: true } }`) instead of a single
relation's options. Doctor's BS210 also flags `facetCounts: true` when PostgREST aggregates are off.
