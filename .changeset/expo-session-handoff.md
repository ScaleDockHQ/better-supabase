---
"better-supabase": minor
---

`bs.middleware()` from `better-supabase/expo` hands the session it refreshed to the loaders and `bs.request` calls of the same request. They read the new cookies without calling Auth again, so a loader with `refresh: false` renders signed in on the first paint after an expired token, and each request makes at most one Auth call. Loaders that run without middleware still refresh on their own.
