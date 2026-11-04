---
"better-supabase": minor
---

Warn about nested private cache scopes. In development `bsb.cached()` logs once when it runs inside another cache scope (best effort, from the async stack), and `better-supabase doctor` reports BS610 for a `"use cache: private"` function that calls another one.
