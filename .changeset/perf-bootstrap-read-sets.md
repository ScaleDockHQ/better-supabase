---
"better-supabase": minor
---

Load a read set with the session check. `blocks.sessions.options.bootstrap` accepts `{ readSets, shell? }`, the wrapper takes `read_set` and `read_params`, and `bsb.bootstrap({ rpc, readSet, params })` returns the decoded result as `reads`. When the request already ran the wrapper, only the read set runs. `db.$decodeReadSet(readSet, params, payload)` decodes a payload that ran elsewhere. Rendering the new wrapper drops the one-argument version.
