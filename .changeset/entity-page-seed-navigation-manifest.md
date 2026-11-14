---
"better-supabase": minor
---

Generate seed rows, a nav item and a route manifest from an entity page.
`gen.entityPages` now writes `pages/<name>.seed.ts` for a page that sets
`seed`, `pages/<name>.navigation.ts` for a page that sets `area`, and
`pages/routes.manifest.ts` with the routes and message keys of every page.
`better-supabase/list` exports the types `EntitySeed`, `EntitySeedValue`,
`EntityNavItem` and `EntityRouteEntry`. A page without `area` or `seed` writes
no new file besides the manifest.
