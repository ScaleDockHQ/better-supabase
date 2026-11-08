---
"better-supabase": minor
---

`server.context(request)` resolves and builds the context directly when neither `tenant` nor `support` is configured; servers that configure either keep the composed path.
