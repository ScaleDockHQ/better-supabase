---
"better-supabase": patch
---

With `createNext()` debug on, a query inside a `"use cache"` or `unstable_cache` scope no longer reads `headers()` to find the request's stats recorder, so a remote cache entry is no longer marked as request-bound and its set no longer fails on every navigation. Queries there are not counted on the request; remote entries still count through their handed-off request id.
