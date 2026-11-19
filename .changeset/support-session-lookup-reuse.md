---
"better-supabase": patch
---

A support session lookup now serves the lookups that follow it for one second, so a render that builds many contexts loads the session once instead of once per context. Concurrent lookups of the target's claims share one call. A stop or revoke on the same instance drops the reused session at once, and each lookup that reaches the store counts as a `support_sessions` call in the request's database stats.
