---
"better-supabase": minor
---

`functionRoute(name, fn, options?)` from `better-supabase/spec` documents a `defineFunction` Edge Function as `POST /functions/v1/<name>`, with its input as the request body and its output as the 200 response. `defineFunction` now keeps its `input`, `output` and a new optional `summary` on the handler it returns, and `TypedFunction` requires them, so `functionRoute` accepts only `defineFunction` handlers.
