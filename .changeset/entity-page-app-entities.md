---
"better-supabase": minor
---

`defineEntityPage` takes two new optional fields and `gen` writes one more file. `tenantOption:
"organizationId"` makes the generated list and export routes pass the request's tenant to a block
whose `page` and `facets` take the organization per call. `app` declares an entity no block owns
(`app.<entity>`) with its surface, table and a reads module, so an app table gets the generated
routes, indexes and scale test. `pages/coverage.ts` lists the routes of each block's pages for the
app's coverage map. Pages that set none of these generate what they did before.
