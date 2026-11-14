---
"better-supabase": minor
---

`gen` now writes the list of an entity page from one descriptor. Declare a page
with `defineEntityPage` (from `better-supabase/list`) in `gen.entityPages.pages`,
and `gen` writes `pages/<name>.list.ts` (a `defineEntityListQuery` over the
entity's declared sorts, facets, filters and search), the
`/api/<name>/list` route, a migration with the indexes of its sorts, facets and
searched columns, and `scale_list_<name>.test.sql`, a pgTAP plan check. A new
doctor check, BS636, reports a declared sort, facet or search column that has
no index. `gen.entityPages` is new and optional, so nothing changes without it.
