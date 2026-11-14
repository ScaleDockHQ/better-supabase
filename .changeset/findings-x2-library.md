---
"better-supabase": minor
---

`run` and `countFacets` of `defineListQuery` take `facetCountMode: "exact" | "capped"`, which overrides the list's config for one call, so a list that caps its chips can still give a dashboard an exact count. The `numbering` block declares `numbering.read` on its `number` entity, and the default admin role holds `numbering.*`. A page that lists the counters can check `numbering.read` instead of `numbering.assign`. Run `better-supabase gen` to write the permission catalog migration, which grants the new key to the owner and admin roles, and `better-supabase upgrade` to refresh the `operation_permission` function. A member also holds `numbering.read`, because every declared `read` key goes to the `member` role.

| Old                                          | New                                                  |
| -------------------------------------------- | ---------------------------------------------------- |
| A numbering page gated by `numbering.assign` | `numbering.read` (the owner, admin and member roles) |
| Facet count mode fixed per list              | `run(db, query, { facetCountMode })` per call        |
