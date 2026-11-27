---
"better-supabase": patch
---

`warm()` opens the PostgREST connection with an `OPTIONS` request instead of a `GET` of `/rest/v1/`, which made PostgREST build the OpenAPI description of every exposed schema during a cold start. `better-supabase/next/instrumentation` adds `warmInBackground(bsb)` for `register()`, which starts the warm-up without making the request that started the instance wait for it.
