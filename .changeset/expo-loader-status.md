---
"better-supabase": patch
---

`bs.loader()` in `better-supabase/expo` turns a `DbException` from `.orThrow()` into a `StatusError` with the error's status, so a missing row answers 404 instead of 500.
