---
"better-supabase": minor
---

Block manifests declare their entities. `defineBlock` takes `entities`, one entry per entity with `mutability` (`editable`, `append-only`, `state-machine` or `read-only`), optional `sorts`, `facets`, `search`, `realtime` and more, and an `emits` flag per method. Every built-in block declares its entities, and `Block.entities` and `AnyBlock.entities` expose them. `better-supabase/blocks` exports the list contract types `PageOptions`, `ListPage`, `FacetResult`, `FacetValue` and `Count` (`{ value, exact }`), the `EntitySurface`, `BlockEntities`, `EntityMutability` and `EntityMethod` types, and the `ENTITY_METHODS` and `ENTITY_MUTABILITIES` lists. `renameBlock` renames the keys of `entities`. No behavior of an existing method changes.

| Before                     | After                                                                              |
| -------------------------- | ---------------------------------------------------------------------------------- |
| No declared entity surface | `defineBlock({ entities: { task: { mutability: "editable" } } })`                  |
| `ListPage` not exported    | `ListPage`, `PageOptions`, `FacetResult` and `Count` from `better-supabase/blocks` |
