---
"better-supabase": minor
---

Read sets accept database functions through `s.$fn.<function>(args)`. The function runs as the caller inside the single `rs_<name>` round trip, must be stable or immutable, and falls back to one `$rpc` call when the read set runs without the generated function.
