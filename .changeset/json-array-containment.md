---
"better-supabase": patch
---

`contains`, `has`, `hasEvery` and `containedBy` on a `json` or `jsonb` column now send the value as a JSON document, also when it is an array. Before, an array value was rendered as a Postgres array literal (`cs.{...}`), which PostgREST rejected with `22P02`, so `where: { parts: { contains: [{ type: "image" }] } }` failed. Array columns still use the array literal. `hasSome` on a json column now returns `invalid_request`, since jsonb has no overlap operator.
