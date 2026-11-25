---
"better-supabase": patch
---

`createFlagsProvider` and `createBetterSupabaseAdapter` take `staleTtl` (default 300000 ms). After `ttl` the previous flag definitions keep serving while one reload runs behind the evaluation, so one request per 30 seconds no longer waits on the Data API. A reload that fails keeps the old definitions until `staleTtl` passes; `staleTtl: 0` restores the earlier behaviour.
