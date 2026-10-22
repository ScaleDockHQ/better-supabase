---
"better-supabase": minor
---

Block clients are keyed by instance. `gen` writes a `blocks.generated.ts`
entry for every instance, with the block it installs, its `uses` and the
function names its SQL writes, plus a renamed client such as `ticketsBlock`.
`createBlocks` reads the entry under the instance key, binds a port that two
blocks provide through the consumer's `uses` or the new `ports` option, and
`createBlockClient` takes `instance`. Block queries use the table key space
`["bsb", instance, method, ...args]`, so `invalidateTables` makes table and
instance queries stale, optionally narrowed to methods.
