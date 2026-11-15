---
"better-supabase": minor
---

Adds `testBlockList` to `better-supabase/testing`: one conformance helper for
the block list contract (ADR 1077). It runs a block entity's `page`, `count`,
`facets` and `get` over seeded rows and checks the keyset walk, the limit, each
sort and a list of sorts, an array filter, `q`, the counts and `get` for an
unknown id. No call is renamed or removed. Each block family adopts the
contract in its own change.
