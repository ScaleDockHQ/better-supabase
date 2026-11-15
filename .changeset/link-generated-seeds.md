---
"better-supabase": minor
---

Generated seeds can link to each other. `seed.rows` on `defineEntityPage` takes
nested lists and objects, `seedRef(entity, name)` for the id of a row another page
seeds, and `seedDate(days)` for a day counted from the day the seed runs. `gen`
writes `dependsOn` into the seed file and stops when a ref names a page without a
seed. `better-supabase/list` exports `seedRef`, `seedDate`, `seedRefs`,
`orderSeeds` and `resolveSeedValue` for a seed runner. The descriptor stays at
`apiVersion: 1`.
