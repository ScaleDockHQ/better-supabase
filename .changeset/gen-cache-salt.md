---
"better-supabase": patch
---

`gen` and `upgrade` no longer serve block SQL from a cache an older generator wrote. The cache key hashed only the CLI's own chunks, while the built CLI loads the SQL generator from `better-supabase/sql`, so after an upgrade that changed a block's subjects a local `gen` could drop search triggers that CI kept. The key now covers all of `dist` (or `src` in a checkout). `gen --check` also reports a file with gen's header that the run no longer writes even when the local manifest is missing, so CI and a local run agree on leftovers. `powersync streams` writes its own header, so `gen` never takes its files for leftovers.
