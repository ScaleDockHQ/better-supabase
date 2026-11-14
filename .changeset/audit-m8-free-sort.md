---
"better-supabase": minor
---

`PageOptions.sort` now accepts a list of up to three sorts as well as one. The list query of an
entity page (`defineEntityListQuery`) reads `sort=a:asc,b:desc` or repeated `sort` parameters,
checks each term against the entity's declared sorts, and writes the list back in `toSearchParams`.
Blocks still order by one declared sort, so their `page` orders by the first term and returns
`sorted: { applied, ignored }` with the terms it left out; the keyset cursor is the cursor of the
applied term. `PageSort`, `SortReport`, `sortsOf` and `MAX_PAGE_SORTS` are exported from
`better-supabase/blocks`. A page declared in `gen.entityPages` can list the multi-column sorts it
offers in `sortLists`; `gen` writes a composite index for each, and doctor rule BS636 reports a
list without it. A custom `page` that reads `options.sort.by` must read `sortsOf(options.sort)`
instead. No `apiVersion` changes.
