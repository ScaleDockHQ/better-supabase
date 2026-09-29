---
'better-supabase': minor
---

Read sets and `db.$many`. `defineReadSet(sb, name, { params }, (s, p) => ({ ... }))` names several
reads with typed placeholders; the `readSets` config key lets `gen` compile each set into a `stable`,
`security invoker` function in the new `read-sets` SQL kit module (BS304 covers drift).
`db.$many(readSet, params)` runs it as one GET over PostgREST and as one transaction over
`better-supabase/postgres`; `db.$many([specA, specB])` returns a typed tuple, in one parallel wave or
one transaction. `Executor` gains an optional `batch(ops)` (checked by `testExecutor`), `SqlClient`
an optional `transaction`, and the rpc context a `get` flag. `next.cacheTags` accepts an array of
specs or a read set.
