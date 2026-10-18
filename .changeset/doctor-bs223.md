---
"better-supabase": minor
---

`doctor` reports BS223 (info) for functions in an exposed schema that return a scalar `int8` or `numeric`, or an array of them. PostgREST sends those as JSON numbers, so values past 2^53 lose precision before `$rpc` sees them; return them as `text` instead.
