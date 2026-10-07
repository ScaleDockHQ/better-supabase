---
"better-supabase": patch
---

`bs.action()` keeps the data type of an action that returns `err(...)` on one path and a `Result` or `AsyncResult` on another. `result.data` was `unknown` for every action that could fail, so callers had to assert the type.
