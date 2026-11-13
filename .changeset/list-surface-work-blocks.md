---
"better-supabase": minor
---

The `inspections`, `meetings` and `warranty` blocks page, facet and count through the shared list implementation (ADR 0749, 0759). `inspections.page`, `meetings.page` and `warranty.page` take `PageOptions` (`q`, `sort`, list `filters`, `after`, `limit`), `facets()` returns the values of each declared facet with counts, and `count()` returns `{ value, exact }`. Their manifests declare `sorts`, `facets`, `filters` and `search`, and the SQL list functions serve all three reads. `warranty` also gains `get(id)` with the SQL function `get_warranty_claim`. The existing `list` methods keep their scalar options. Run `better-supabase upgrade` and apply the new migration to adopt the new list functions.

| Before                                                              | After                                                                                         |
| ------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `inspections.list({ status })` with `offset` for the next page      | `inspections.page({ filters: { status: ["planned", "in_progress"] }, sort, after })`          |
| `meetings.list({ search, from, to })` with `offset`                 | `meetings.page({ q, filters: { from: [start], to: [end] }, sort, after })`                    |
| `warranty.list({ status })` with `offset`                           | `warranty.page({ filters: { status: ["submitted"] }, sort: { by: "amount" }, after })`        |
| No facet counts or exact counts on these three blocks               | `facets()` and `count()` on each, with `{ value, exact }` counts                              |
| A claim detail page read the claim from the list                    | `warranty.get(id)`                                                                            |
