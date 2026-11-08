---
"better-supabase": patch
---

`createNext` resolves a request's auth once per read of `context()` or `claims()`: the extra snapshot pass is gone and the claims are derived from the one resolution.
