---
"better-supabase": patch
---

`parseDbStats` reads the `x-bsb-db-calls` header when `debug.coldStart` appends its `cold=` field. Before, the extra field made every number `NaN` and the parser returned `undefined`.
